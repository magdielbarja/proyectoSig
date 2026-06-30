const express = require('express');
const cors = require('cors');
const db = require('./db');
const { findOptimalRoute, findAlternativeRoutes, haversine } = require('./dijkstra');

require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Logger middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// 1. GET /api/lines - List all microbus lines
app.get('/api/lines', async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM lineas ORDER BY nombre_linea ASC');
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching lines:', err);
    res.status(500).json({ error: 'Database error fetching lines' });
  }
});

// 3. GET /api/lines/near - Find lines passing near a coordinate
app.get('/api/lines/near', async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lon = parseFloat(req.query.lon);
  const radiusMeters = parseFloat(req.query.radius) || 500.0;
  const radiusKm = radiusMeters / 1000.0;

  if (isNaN(lat) || isNaN(lon)) {
    return res.status(400).json({ error: 'lat and lon query parameters are required and must be numbers' });
  }

  try {
    // Query distinct lines passing through points within the specified radius
    // We calculate the Haversine distance directly in SQL to make it fast and avoid pg array parsing errors.
    const query = `
      SELECT DISTINCT l.id_linea, l.nombre_linea, l.color_linea, l.imagen_microbus
      FROM lineas_puntos lp
      JOIN linea_ruta lr ON lp.id_linea_ruta = lr.id_linea_ruta
      JOIN lineas l ON lr.id_linea = l.id_linea
      JOIN puntos p ON (lp.id_punto = p.id_point OR lp.id_punto_dest = p.id_point)
      WHERE (
        6371.0 * 2.0 * ASIN(LEAST(1.0, SQRT(GREATEST(0.0, 
          POWER(SIN((p.latitud - $1) * pi() / 360.0), 2) +
          COS($1 * pi() / 180.0) * COS(p.latitud * pi() / 180.0) *
          POWER(SIN((p.longitud - $2) * pi() / 360.0), 2)
        )))) <= $3
      )
      ORDER BY l.nombre_linea ASC
    `;
    const linesRes = await db.query(query, [lat, lon, radiusKm]);
    res.json(linesRes.rows);
  } catch (err) {
    console.error('Error finding near lines:', err);
    res.status(500).json({ error: 'Database error finding near lines' });
  }
});

// 2. GET /api/lines/:id - Get full route details for a specific line (ida y retorno)
app.get('/api/lines/:id', async (req, res) => {
  const lineId = parseInt(req.params.id);
  try {
    // Fetch line metadata
    const lineRes = await db.query('SELECT * FROM lineas WHERE id_linea = $1', [lineId]);
    if (lineRes.rows.length === 0) {
      return res.status(404).json({ error: 'Line not found' });
    }

    // Fetch routes for this line (ida vs retorno)
    const routesRes = await db.query('SELECT * FROM linea_ruta WHERE id_linea = $1 ORDER BY id_ruta ASC', [lineId]);

    const result = {
      line: lineRes.rows[0],
      routes: []
    };

    // For each route, fetch the ordered list of points
    for (const route of routesRes.rows) {
      // Query to get all points ordered by segment order
      const pointsQuery = `
        SELECT lp.orden, lp.distancia, lp.tiempo, p.id_point, p.latitud, p.longitud, p.descripcion, p.stop
        FROM lineas_puntos lp
        JOIN puntos p ON lp.id_punto = p.id_point
        WHERE lp.id_linea_ruta = $1
        ORDER BY lp.orden ASC
      `;
      const pointsRes = await db.query(pointsQuery, [route.id_linea_ruta]);
      
      // If there are points, add the destination point of the last segment to complete the line coordinates
      const pointsList = pointsRes.rows;
      if (pointsList.length > 0) {
        const lastSegQuery = `
          SELECT p.id_point, p.latitud, p.longitud, p.descripcion, p.stop
          FROM lineas_puntos lp
          JOIN puntos p ON lp.id_punto_dest = p.id_point
          WHERE lp.id_linea_ruta = $1 AND lp.id_punto_dest IS NOT NULL
          ORDER BY lp.orden DESC
          LIMIT 1
        `;
        const lastPointRes = await db.query(lastSegQuery, [route.id_linea_ruta]);
        if (lastPointRes.rows.length > 0) {
          const lp = lastPointRes.rows[0];
          pointsList.push({
            orden: pointsList.length + 1,
            distancia: 0,
            tiempo: 0,
            id_point: lp.id_point,
            latitud: lp.latitud,
            longitud: lp.longitud,
            descripcion: lp.descripcion,
            stop: lp.stop
          });
        }
      }

      result.routes.push({
        id_linea_ruta: route.id_linea_ruta,
        id_ruta: route.id_ruta,
        descripcion: route.descripcion,
        total_distancia_km: route.distancia,
        total_tiempo_horas: route.tiempo,
        points: pointsList
      });
    }

    res.json(result);
  } catch (err) {
    console.error(`Error fetching line ${lineId}:`, err);
    res.status(500).json({ error: 'Database error fetching line details' });
  }
});

// 4. GET /api/route - Compute optimal route (Dijkstra)
app.get('/api/route', async (req, res) => {
  const fromLat = parseFloat(req.query.fromLat);
  const fromLon = parseFloat(req.query.fromLon);
  const toLat = parseFloat(req.query.toLat);
  const toLon = parseFloat(req.query.toLon);
  
  const mode = req.query.mode || 'smart'; // 'smart' or 'official'
  const metric = req.query.metric || 'time'; // 'time' or 'distance'
  const walkSpeed = parseFloat(req.query.walkSpeed) || 4.0; // km/h
  const transferPenalty = parseFloat(req.query.transferPenalty) || 5.0; // minutes

  if (isNaN(fromLat) || isNaN(fromLon) || isNaN(toLat) || isNaN(toLon)) {
    return res.status(400).json({ error: 'fromLat, fromLon, toLat, and toLon are required and must be numbers' });
  }

  try {
    const routeResult = await findAlternativeRoutes(
      fromLat, fromLon,
      toLat, toLon,
      mode,
      metric,
      walkSpeed,
      transferPenalty
    );

    if (!routeResult || routeResult.length === 0) {
      return res.status(404).json({ error: 'No route found between the specified locations.' });
    }

    res.json({ routes: routeResult });
  } catch (err) {
    console.error('Error running Dijkstra router:', err);
    res.status(500).json({ error: 'Internal router error calculating route' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Express API Server running on port ${PORT}`);
  console.log(`Endpoints available:`);
  console.log(`  - GET http://localhost:${PORT}/api/lines`);
  console.log(`  - GET http://localhost:${PORT}/api/lines/:id`);
  console.log(`  - GET http://localhost:${PORT}/api/lines/near?lat=-17.78&lon=-63.17&radius=500`);
  console.log(`  - GET http://localhost:${PORT}/api/route?fromLat=-17.782&fromLon=-63.170&toLat=-17.780&toLon=-63.172`);
});
