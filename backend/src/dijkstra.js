const db = require('./db');

// Haversine formula to compute distance in km between two coordinates
function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371.0; // km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Priority Queue implementation for Dijkstra (Min-Heap)
class PriorityQueue {
  constructor() {
    this.values = [];
  }
  enqueue(val, priority) {
    this.values.push({ val, priority });
    this.sort();
  }
  dequeue() {
    return this.values.shift();
  }
  sort() {
    this.values.sort((a, b) => a.priority - b.priority);
  }
  isEmpty() {
    return this.values.length === 0;
  }
}

/**
 * Finds the optimal route between coordinates (startLat, startLon) and (endLat, endLon).
 * @param {number} startLat
 * @param {number} startLon
 * @param {number} endLat
 * @param {number} endLon
 * @param {string} mode 'official' (only use points_trasbordos table) or 'smart' (any intersecting stop)
 * @param {string} metric 'time' (optimizes for total hours) or 'distance' (optimizes for total km)
 * @param {number} walkSpeed km/h, defaults to 4.0
 * @param {number} defaultTransferPenalty min, defaults to 5.0
 */
async function findOptimalRoute(startLat, startLon, endLat, endLon, mode = 'smart', metric = 'time', walkSpeed = 4.0, defaultTransferPenalty = 5.0) {
  console.log(`Calculating route from (${startLat}, ${startLon}) to (${endLat}, ${endLon}) using mode=${mode}, metric=${metric}`);

  // 1. Load network data from database
  const linesRes = await db.query('SELECT * FROM lineas');
  const pointsRes = await db.query('SELECT * FROM puntos');
  const routesRes = await db.query('SELECT * FROM linea_ruta');
  const segmentsRes = await db.query('SELECT * FROM lineas_puntos ORDER BY id_linea_ruta, orden');
  const transfersRes = await db.query('SELECT * FROM puntos_trasbordos');

  const linesMap = new Map(linesRes.rows.map(l => [l.id_linea, l]));
  const pointsMap = new Map(pointsRes.rows.map(p => [p.id_point, p]));
  const routesMap = new Map(routesRes.rows.map(r => [r.id_linea_ruta, r]));

  const points = pointsRes.rows;
  const segments = segmentsRes.rows;

  // 2. Identify which routes pass through each physical point
  // pointToRoutesMap: id_punto -> Set of id_linea_ruta
  const pointToRoutesMap = new Map();
  for (const seg of segments) {
    if (!pointToRoutesMap.has(seg.id_punto)) {
      pointToRoutesMap.set(seg.id_punto, new Set());
    }
    pointToRoutesMap.get(seg.id_punto).add(seg.id_linea_ruta);
  }

  // 3. Build Adjacency List for Routing
  // Graph Nodes: string representation "pointId_routeId"
  const adj = new Map();

  // Travel edges (consecutive segments along a route)
  for (const seg of segments) {
    if (seg.id_punto_dest === null) continue; // End of route

    const u = `${seg.id_punto}_${seg.id_linea_ruta}`;
    const v = `${seg.id_punto_dest}_${seg.id_linea_ruta}`;

    const dist = seg.distancia;
    const time = seg.tiempo; // in hours

    const weight = metric === 'time' ? time : dist;

    if (!adj.has(u)) adj.set(u, []);
    adj.get(u).push({
      to: v,
      weight,
      dist,
      time,
      type: 'TRAVEL',
      detail: seg.id_linea_ruta
    });
  }

  // Transfer edges
  if (mode === 'official') {
    // Use only table puntos_trasbordos
    for (const tf of transfersRes.rows) {
      const pId = tf.id_punto;
      const rOrig = tf.id_linea_origen; // Route ID in database!
      const rDest = tf.id_linea_destino; // Route ID in database!
      const penaltyHours = tf.penalizacion_min / 60.0;
      const penaltyWeight = metric === 'time' ? penaltyHours : 0.0;

      // Ensure that both routes actually pass through pId in the graph
      const passesOrig = pointToRoutesMap.get(pId)?.has(rOrig);
      const passesDest = pointToRoutesMap.get(pId)?.has(rDest);

      if (passesOrig && passesDest) {
        const u = `${pId}_${rOrig}`;
        const v = `${pId}_${rDest}`;

        if (!adj.has(u)) adj.set(u, []);
        adj.get(u).push({
          to: v,
          weight: penaltyWeight,
          dist: 0.0,
          time: penaltyHours,
          type: 'TRANSFER',
          detail: routesMap.get(rDest).id_linea // Destination Line ID
        });
      }
    }
  } else {
    // Smart/Intersection mode: transfer between ANY routes sharing a physical point
    for (const [pId, rSet] of pointToRoutesMap.entries()) {
      if (rSet.size < 2) continue;

      const rList = Array.from(rSet);
      for (let i = 0; i < rList.length; i++) {
        for (let j = 0; j < rList.length; j++) {
          if (i === j) continue;

          const rOrig = rList[i];
          const rDest = rList[j];
          const lineOrig = routesMap.get(rOrig).id_linea;
          const lineDest = routesMap.get(rDest).id_linea;

          // If different lines, apply a penalty. If same line (e.g. Salida to Retorno), smaller penalty.
          let penaltyMin = defaultTransferPenalty;
          if (lineOrig === lineDest) {
            penaltyMin = 2.0; // 2 minutes to switch to return route of same line
          }

          const penaltyHours = penaltyMin / 60.0;
          const penaltyWeight = metric === 'time' ? penaltyHours : 0.0;

          const u = `${pId}_${rOrig}`;
          const v = `${pId}_${rDest}`;

          if (!adj.has(u)) adj.set(u, []);
          adj.get(u).push({
            to: v,
            weight: penaltyWeight,
            dist: 0.0,
            time: penaltyHours,
            type: 'TRANSFER',
            detail: lineDest
          });
        }
      }
    }
  }

  // 4. Connect Start and End coordinates to the network
  // Find points near Start (within 1.0 km) and near End (within 1.0 km)
  let startCandidates = [];
  let endCandidates = [];

  for (const pt of points) {
    const dStart = haversine(startLat, startLon, pt.latitud, pt.longitud);
    const dEnd = haversine(endLat, endLon, pt.latitud, pt.longitud);

    if (dStart <= 1.2) {
      startCandidates.push({ point: pt, dist: dStart });
    }
    if (dEnd <= 1.2) {
      endCandidates.push({ point: pt, dist: dEnd });
    }
  }

  // Fallback: If no points within 1.2km, fetch the 3 nearest points
  if (startCandidates.length === 0) {
    const sorted = points.map(pt => ({ point: pt, dist: haversine(startLat, startLon, pt.latitud, pt.longitud) }))
      .sort((a, b) => a.dist - b.dist);
    startCandidates = sorted.slice(0, 3);
  }
  if (endCandidates.length === 0) {
    const sorted = points.map(pt => ({ point: pt, dist: haversine(endLat, endLon, pt.latitud, pt.longitud) }))
      .sort((a, b) => a.dist - b.dist);
    endCandidates = sorted.slice(0, 3);
  }

  // Add virtual START and END connections in the adjacency list
  adj.set('START', []);

  for (const cand of startCandidates) {
    const pId = cand.point.id_point;
    const walkDist = cand.dist;
    const walkTime = walkDist / walkSpeed; // in hours
    const walkWeight = metric === 'time' ? walkTime : walkDist;

    // Connect START to all (pId, rId) nodes for routes passing through pId
    const rSet = pointToRoutesMap.get(pId) || new Set();
    for (const rId of rSet) {
      const v = `${pId}_${rId}`;
      adj.get('START').push({
        to: v,
        weight: walkWeight,
        dist: walkDist,
        time: walkTime,
        type: 'WALK',
        detail: 'START_WALK'
      });
    }
  }

  // Connect candidate end nodes to virtual END node
  for (const cand of endCandidates) {
    const pId = cand.point.id_point;
    const walkDist = cand.dist;
    const walkTime = walkDist / walkSpeed;
    const walkWeight = metric === 'time' ? walkTime : walkDist;

    const rSet = pointToRoutesMap.get(pId) || new Set();
    for (const rId of rSet) {
      const u = `${pId}_${rId}`;
      if (!adj.has(u)) adj.set(u, []);
      adj.get(u).push({
        to: 'END',
        weight: walkWeight,
        dist: walkDist,
        time: walkTime,
        type: 'WALK',
        detail: 'END_WALK'
      });
    }
  }

  // 5. Run Dijkstra's Algorithm
  const dist = {}; // nodeKey -> minWeight
  const parent = {}; // nodeKey -> { parentKey, edgeInfo }

  const pq = new PriorityQueue();

  dist['START'] = 0.0;
  pq.enqueue('START', 0.0);

  const visited = new Set();

  while (!pq.isEmpty()) {
    const { val: u } = pq.dequeue();

    if (u === 'END') break; // Found shortest path to destination

    if (visited.has(u)) continue;
    visited.add(u);

    const edges = adj.get(u) || [];
    for (const edge of edges) {
      const v = edge.to;
      if (visited.has(v)) continue;

      const alt = dist[u] + edge.weight;

      if (dist[v] === undefined || alt < dist[v]) {
        dist[v] = alt;
        parent[v] = { parentKey: u, edge };
        pq.enqueue(v, alt);
      }
    }
  }

  if (dist['END'] === undefined) {
    return null; // Route not found
  }

  // 6. Reconstruct path
  const rawPath = [];
  let curr = 'END';
  while (curr !== 'START') {
    const step = parent[curr];
    rawPath.push({ node: curr, edge: step.edge });
    curr = step.parentKey;
  }
  rawPath.reverse();

  // 7. Group and format path steps for clean API response
  const legs = [];
  let currentLeg = null;

  for (const step of rawPath) {
    const edge = step.edge;
    const type = edge.type;
    const toNode = step.node;

    if (type === 'WALK') {
      if (edge.detail === 'START_WALK') {
        const destPointId = parseInt(toNode.split('_')[0]);
        const destPoint = pointsMap.get(destPointId);
        legs.push({
          type: 'WALK',
          description: `Camina desde el origen hasta la parada ${destPoint.descripcion}`,
          distance: edge.dist,
          time: edge.time * 60, // to minutes
          points: [
            { lat: startLat, lon: startLon },
            { lat: destPoint.latitud, lon: destPoint.longitud }
          ]
        });
      } else if (edge.detail === 'END_WALK') {
        const fromPointId = parseInt(step.edge.to === 'END' ? rawPath[rawPath.indexOf(step) - 1].node.split('_')[0] : 0);
        // Wait, let's parse the from point safely
        const fromNode = rawPath[rawPath.indexOf(step) - 1]?.node || '';
        const fromPointIdParsed = parseInt(fromNode.split('_')[0]);
        const fromPoint = pointsMap.get(fromPointIdParsed);
        legs.push({
          type: 'WALK',
          description: `Camina desde la parada ${fromPoint ? fromPoint.descripcion : ''} hasta el destino`,
          distance: edge.dist,
          time: edge.time * 60, // to minutes
          points: [
            { lat: fromPoint ? fromPoint.latitud : endLat, lon: fromPoint ? fromPoint.longitud : endLon },
            { lat: endLat, lon: endLon }
          ]
        });
      }
    } else if (type === 'TRANSFER') {
      const pId = parseInt(toNode.split('_')[0]);
      const pt = pointsMap.get(pId);
      const destLineId = edge.detail;
      const destLine = linesMap.get(destLineId);
      legs.push({
        type: 'TRANSFER',
        description: `Transbordo en la parada ${pt.descripcion} hacia la Línea ${destLine.nombre_linea}`,
        distance: 0.0,
        time: edge.time * 60,
        points: [
          { lat: pt.latitud, lon: pt.longitud }
        ]
      });
      // Reset current board leg
      currentLeg = null;
    } else if (type === 'TRAVEL') {
      const routeId = edge.detail;
      const routeInfo = routesMap.get(routeId);
      const lineInfo = linesMap.get(routeInfo.id_linea);

      const toPointId = parseInt(toNode.split('_')[0]);
      const toPoint = pointsMap.get(toPointId);

      if (currentLeg && currentLeg.routeId === routeId) {
        // Continue traveling on the same line/route
        currentLeg.distance += edge.dist;
        currentLeg.time += edge.time * 60;
        currentLeg.stopsCount += 1;
        currentLeg.points.push({ lat: toPoint.latitud, lon: toPoint.longitud, stop: toPoint.stop });
        currentLeg.description = `Viaja en Línea ${lineInfo.nombre_linea} (${routeInfo.descripcion}) durante ${currentLeg.stopsCount} paradas`;
      } else {
        // Start a new travel leg
        const fromNode = rawPath[rawPath.indexOf(step) - 1].node;
        const fromPointId = parseInt(fromNode.split('_')[0]);
        const fromPoint = pointsMap.get(fromPointId);

        currentLeg = {
          type: 'TRAVEL',
          routeId,
          lineId: routeInfo.id_linea,
          lineName: lineInfo.nombre_linea,
          lineColor: lineInfo.color_linea,
          description: `Súbete a la Línea ${lineInfo.nombre_linea} (${routeInfo.descripcion})`,
          distance: edge.dist,
          time: edge.time * 60, // in minutes
          stopsCount: 1,
          points: [
            { lat: fromPoint.latitud, lon: fromPoint.longitud, stop: fromPoint.stop },
            { lat: toPoint.latitud, lon: toPoint.longitud, stop: toPoint.stop }
          ]
        };
        legs.push(currentLeg);
      }
    }
  }

  // Calculate total summaries
  let totalTime = 0.0;
  let totalDistance = 0.0;
  for (const leg of legs) {
    totalTime += leg.time;
    totalDistance += leg.distance;
  }

  return {
    totalTimeMin: totalTime,
    totalDistanceKm: totalDistance,
    legs
  };
}

// Computes up to 3 alternative routes: direct routes first, then optimal & alternative transfer paths
async function findAlternativeRoutes(startLat, startLon, endLat, endLon, mode = 'smart', metric = 'time', walkSpeed = 4.0, defaultTransferPenalty = 5.0) {
  console.log(`Calculating alternative routes from (${startLat}, ${startLon}) to (${endLat}, ${endLon})`);

  // 1. Load data from DB
  const linesRes = await db.query('SELECT * FROM lineas');
  const pointsRes = await db.query('SELECT * FROM puntos');
  const routesRes = await db.query('SELECT * FROM linea_ruta');
  const segmentsRes = await db.query('SELECT * FROM lineas_puntos ORDER BY id_linea_ruta, orden');
  const transfersRes = await db.query('SELECT * FROM puntos_trasbordos');

  const linesMap = new Map(linesRes.rows.map(l => [l.id_linea, l]));
  const pointsMap = new Map(pointsRes.rows.map(p => [p.id_point, p]));
  const routesMap = new Map(routesRes.rows.map(r => [r.id_linea_ruta, r]));

  const points = pointsRes.rows;
  const segments = segmentsRes.rows;

  // 2. Identify start and end candidate points (within 1.2 km)
  const startCandidates = [];
  const endCandidates = [];

  for (const pt of points) {
    const dStart = haversine(startLat, startLon, pt.latitud, pt.longitud);
    const dEnd = haversine(endLat, endLon, pt.latitud, pt.longitud);

    if (dStart <= 1.2) {
      startCandidates.push({ point: pt, dist: dStart });
    }
    if (dEnd <= 1.2) {
      endCandidates.push({ point: pt, dist: dEnd });
    }
  }

  // Fallback if none found
  if (startCandidates.length === 0) {
    const sorted = points.map(pt => ({ point: pt, dist: haversine(startLat, startLon, pt.latitud, pt.longitud) }))
      .sort((a, b) => a.dist - b.dist);
    startCandidates.push(...sorted.slice(0, 3));
  }
  if (endCandidates.length === 0) {
    const sorted = points.map(pt => ({ point: pt, dist: haversine(endLat, endLon, pt.latitud, pt.longitud) }))
      .sort((a, b) => a.dist - b.dist);
    endCandidates.push(...sorted.slice(0, 3));
  }

  const startPointIds = new Set(startCandidates.map(c => c.point.id_point));
  const endPointIds = new Set(endCandidates.map(c => c.point.id_point));

  // 3. Find Direct Routes
  // Map segments by route
  const routeSegmentsListMap = new Map();
  for (const seg of segments) {
    if (!routeSegmentsListMap.has(seg.id_linea_ruta)) {
      routeSegmentsListMap.set(seg.id_linea_ruta, []);
    }
    routeSegmentsListMap.get(seg.id_linea_ruta).push(seg);
  }

  const directRoutes = [];
  for (const [rId, segs] of routeSegmentsListMap.entries()) {
    // Sort segments by orden to be sure
    segs.sort((a, b) => a.orden - b.orden);

    // Find first start candidate point in this route
    let minStartSeg = null;
    for (const seg of segs) {
      if (startPointIds.has(seg.id_punto)) {
        minStartSeg = seg;
        break;
      }
    }

    // Find last end candidate point in this route
    let maxEndSeg = null;
    for (let i = segs.length - 1; i >= 0; i--) {
      const seg = segs[i];
      if (endPointIds.has(seg.id_punto) || (seg.id_punto_dest && endPointIds.has(seg.id_punto_dest))) {
        maxEndSeg = seg;
        break;
      }
    }

    if (minStartSeg && maxEndSeg && minStartSeg.orden <= maxEndSeg.orden) {
      // Build the travel points and stats
      const travelPoints = [];
      let travelDist = 0.0;
      let travelTime = 0.0;
      let stopsCount = 0;

      for (const seg of segs) {
        if (seg.orden >= minStartSeg.orden && seg.orden <= maxEndSeg.orden) {
          const pt = pointsMap.get(seg.id_punto);
          travelPoints.push({ lat: pt.latitud, lon: pt.longitud, stop: pt.stop });
          travelDist += seg.distancia;
          travelTime += seg.tiempo * 60; // in minutes
          stopsCount++;
        }
      }

      // Add final destination point
      const lastSeg = maxEndSeg;
      if (lastSeg.id_punto_dest) {
        const destPt = pointsMap.get(lastSeg.id_punto_dest);
        travelPoints.push({ lat: destPt.latitud, lon: destPt.longitud, stop: destPt.stop });
      }

      // Walk 1
      const startPt = pointsMap.get(minStartSeg.id_punto);
      const walk1Dist = haversine(startLat, startLon, startPt.latitud, startPt.longitud);
      const walk1Time = (walk1Dist / walkSpeed) * 60; // in minutes

      // Walk 2
      const endPt = lastSeg.id_punto_dest ? pointsMap.get(lastSeg.id_punto_dest) : pointsMap.get(lastSeg.id_punto);
      const walk2Dist = haversine(endPt.latitud, endPt.longitud, endLat, endLon);
      const walk2Time = (walk2Dist / walkSpeed) * 60; // in minutes

      const routeInfo = routesMap.get(rId);
      const lineInfo = linesMap.get(routeInfo.id_linea);

      const legs = [
        {
          type: 'WALK',
          description: `Camina desde el origen hasta la parada ${startPt.descripcion}`,
          distance: walk1Dist,
          time: walk1Time,
          points: [
            { lat: startLat, lon: startLon },
            { lat: startPt.latitud, lon: startPt.longitud }
          ]
        },
        {
          type: 'TRAVEL',
          routeId: rId,
          lineId: routeInfo.id_linea,
          lineName: lineInfo.nombre_linea,
          lineColor: lineInfo.color_linea,
          description: `Súbete a la Línea ${lineInfo.nombre_linea.trim()} (${routeInfo.descripcion.trim()})`,
          distance: travelDist,
          time: travelTime,
          stopsCount: stopsCount,
          points: travelPoints
        },
        {
          type: 'WALK',
          description: `Camina desde la parada ${endPt.descripcion} hasta el destino`,
          distance: walk2Dist,
          time: walk2Time,
          points: [
            { lat: endPt.latitud, lon: endPt.longitud },
            { lat: endLat, lon: endLon }
          ]
        }
      ];

      directRoutes.push({
        totalTimeMin: walk1Time + travelTime + walk2Time,
        totalDistanceKm: walk1Dist + travelDist + walk2Dist,
        legs,
        isDirect: true
      });
    }
  }

  // 4. Build base graph adjacency list for Dijkstra runs
  const pointToRoutesMap = new Map();
  for (const seg of segments) {
    if (!pointToRoutesMap.has(seg.id_punto)) {
      pointToRoutesMap.set(seg.id_punto, new Set());
    }
    pointToRoutesMap.get(seg.id_punto).add(seg.id_linea_ruta);
  }

  function buildAdjacencyList(penalizedLines = new Set()) {
    const adj = new Map();

    // Travel edges
    for (const seg of segments) {
      if (seg.id_punto_dest === null) continue;

      const u = `${seg.id_punto}_${seg.id_linea_ruta}`;
      const v = `${seg.id_punto_dest}_${seg.id_linea_ruta}`;

      const dist = seg.distancia;
      const time = seg.tiempo; // hours

      let weight = metric === 'time' ? time : dist;

      // Apply penalty if line is penalized
      const routeInfo = routesMap.get(seg.id_linea_ruta);
      if (routeInfo && penalizedLines.has(routeInfo.id_linea)) {
        weight += metric === 'time' ? 1.0 : 15.0; // Penalty weight: 1 hour or 15 km
      }

      if (!adj.has(u)) adj.set(u, []);
      adj.get(u).push({
        to: v,
        weight,
        dist,
        time,
        type: 'TRAVEL',
        detail: seg.id_linea_ruta
      });
    }

    // Transfer edges
    if (mode === 'official') {
      for (const tf of transfersRes.rows) {
        const pId = tf.id_punto;
        const rOrig = tf.id_linea_origen;
        const rDest = tf.id_linea_destino;
        const penaltyHours = tf.penalizacion_min / 60.0;
        const penaltyWeight = metric === 'time' ? penaltyHours : 0.0;

        const passesOrig = pointToRoutesMap.get(pId)?.has(rOrig);
        const passesDest = pointToRoutesMap.get(pId)?.has(rDest);

        if (passesOrig && passesDest) {
          const u = `${pId}_${rOrig}`;
          const v = `${pId}_${rDest}`;

          if (!adj.has(u)) adj.set(u, []);
          adj.get(u).push({
            to: v,
            weight: penaltyWeight,
            dist: 0.0,
            time: penaltyHours,
            type: 'TRANSFER',
            detail: routesMap.get(rDest).id_linea
          });
        }
      }
    } else {
      for (const [pId, rSet] of pointToRoutesMap.entries()) {
        if (rSet.size < 2) continue;

        const rList = Array.from(rSet);
        for (let i = 0; i < rList.length; i++) {
          for (let j = 0; j < rList.length; j++) {
            if (i === j) continue;

            const rOrig = rList[i];
            const rDest = rList[j];
            const lineOrig = routesMap.get(rOrig).id_linea;
            const lineDest = routesMap.get(rDest).id_linea;

            let penaltyMin = defaultTransferPenalty;
            if (lineOrig === lineDest) {
              penaltyMin = 2.0;
            }

            const penaltyHours = penaltyMin / 60.0;
            const penaltyWeight = metric === 'time' ? penaltyHours : 0.0;

            const u = `${pId}_${rOrig}`;
            const v = `${pId}_${rDest}`;

            if (!adj.has(u)) adj.set(u, []);
            adj.get(u).push({
              to: v,
              weight: penaltyWeight,
              dist: 0.0,
              time: penaltyHours,
              type: 'TRANSFER',
              detail: lineDest
            });
          }
        }
      }
    }

    // Connect START and END virtual nodes
    adj.set('START', []);

    for (const cand of startCandidates) {
      const pId = cand.point.id_point;
      const walkDist = cand.dist;
      const walkTime = walkDist / walkSpeed;
      const walkWeight = metric === 'time' ? walkTime : walkDist;

      const rSet = pointToRoutesMap.get(pId) || new Set();
      for (const rId of rSet) {
        const v = `${pId}_${rId}`;
        adj.get('START').push({
          to: v,
          weight: walkWeight,
          dist: walkDist,
          time: walkTime,
          type: 'WALK',
          detail: 'START_WALK'
        });
      }
    }

    for (const cand of endCandidates) {
      const pId = cand.point.id_point;
      const walkDist = cand.dist;
      const walkTime = walkDist / walkSpeed;
      const walkWeight = metric === 'time' ? walkTime : walkDist;

      const rSet = pointToRoutesMap.get(pId) || new Set();
      for (const rId of rSet) {
        const u = `${pId}_${rId}`;
        if (!adj.has(u)) adj.set(u, []);
        adj.get(u).push({
          to: 'END',
          weight: walkWeight,
          dist: walkDist,
          time: walkTime,
          type: 'WALK',
          detail: 'END_WALK'
        });
      }
    }

    return adj;
  }

  // Core Dijkstra run function
  function runDijkstraSearch(adjList) {
    const dist = {};
    const parent = {};
    const pq = new PriorityQueue();

    dist['START'] = 0.0;
    pq.enqueue('START', 0.0);

    const visited = new Set();

    while (!pq.isEmpty()) {
      const { val: u } = pq.dequeue();

      if (u === 'END') break;

      if (visited.has(u)) continue;
      visited.add(u);

      const edges = adjList.get(u) || [];
      for (const edge of edges) {
        const v = edge.to;
        if (visited.has(v)) continue;

        const alt = dist[u] + edge.weight;

        if (dist[v] === undefined || alt < dist[v]) {
          dist[v] = alt;
          parent[v] = { parentKey: u, edge };
          pq.enqueue(v, alt);
        }
      }
    }

    if (dist['END'] === undefined) {
      return null;
    }

    // Reconstruct path
    const rawPath = [];
    let curr = 'END';
    while (curr !== 'START') {
      const step = parent[curr];
      rawPath.push({ node: curr, edge: step.edge });
      curr = step.parentKey;
    }
    rawPath.reverse();

    // Group legs
    const legs = [];
    let currentLeg = null;

    for (const step of rawPath) {
      const edge = step.edge;
      const type = edge.type;
      const toNode = step.node;

      if (type === 'WALK') {
        if (edge.detail === 'START_WALK') {
          const destPointId = parseInt(toNode.split('_')[0]);
          const destPoint = pointsMap.get(destPointId);
          legs.push({
            type: 'WALK',
            description: `Camina desde el origen hasta la parada ${destPoint.descripcion}`,
            distance: edge.dist,
            time: edge.time * 60,
            points: [
              { lat: startLat, lon: startLon },
              { lat: destPoint.latitud, lon: destPoint.longitud }
            ]
          });
        } else if (edge.detail === 'END_WALK') {
          const fromNode = rawPath[rawPath.indexOf(step) - 1]?.node || '';
          const fromPointIdParsed = parseInt(fromNode.split('_')[0]);
          const fromPoint = pointsMap.get(fromPointIdParsed);
          legs.push({
            type: 'WALK',
            description: `Camina desde la parada ${fromPoint ? fromPoint.descripcion : ''} hasta el destino`,
            distance: edge.dist,
            time: edge.time * 60,
            points: [
              { lat: fromPoint ? fromPoint.latitud : endLat, lon: fromPoint ? fromPoint.longitud : endLon },
              { lat: endLat, lon: endLon }
            ]
          });
        }
      } else if (type === 'TRANSFER') {
        const pId = parseInt(toNode.split('_')[0]);
        const pt = pointsMap.get(pId);
        const destLineId = edge.detail;
        const destLine = linesMap.get(destLineId);
        legs.push({
          type: 'TRANSFER',
          description: `Transbordo en la parada ${pt.descripcion} hacia la Línea ${destLine.nombre_linea.trim()}`,
          distance: 0.0,
          time: edge.time * 60,
          points: [
            { lat: pt.latitud, lon: pt.longitud }
          ]
        });
        currentLeg = null;
      } else if (type === 'TRAVEL') {
        const routeId = edge.detail;
        const routeInfo = routesMap.get(routeId);
        const lineInfo = linesMap.get(routeInfo.id_linea);

        const toPointId = parseInt(toNode.split('_')[0]);
        const toPoint = pointsMap.get(toPointId);

        if (currentLeg && currentLeg.routeId === routeId) {
          currentLeg.distance += edge.dist;
          currentLeg.time += edge.time * 60;
          currentLeg.stopsCount += 1;
          currentLeg.points.push({ lat: toPoint.latitud, lon: toPoint.longitud, stop: toPoint.stop });
          currentLeg.description = `Viaja en Línea ${lineInfo.nombre_linea.trim()} (${routeInfo.descripcion.trim()}) durante ${currentLeg.stopsCount} paradas`;
        } else {
          const fromNode = rawPath[rawPath.indexOf(step) - 1].node;
          const fromPointId = parseInt(fromNode.split('_')[0]);
          const fromPoint = pointsMap.get(fromPointId);

          currentLeg = {
            type: 'TRAVEL',
            routeId,
            lineId: routeInfo.id_linea,
            lineName: lineInfo.nombre_linea,
            lineColor: lineInfo.color_linea,
            description: `Súbete a la Línea ${lineInfo.nombre_linea.trim()} (${routeInfo.descripcion.trim()})`,
            distance: edge.dist,
            time: edge.time * 60,
            stopsCount: 1,
            points: [
              { lat: fromPoint.latitud, lon: fromPoint.longitud, stop: fromPoint.stop },
              { lat: toPoint.latitud, lon: toPoint.longitud, stop: toPoint.stop }
            ]
          };
          legs.push(currentLeg);
        }
      }
    }

    let totalTime = 0.0;
    let totalDistance = 0.0;
    for (const leg of legs) {
      totalTime += leg.time;
      totalDistance += leg.distance;
    }

    return {
      totalTimeMin: totalTime,
      totalDistanceKm: totalDistance,
      legs,
      isDirect: legs.filter(l => l.type === 'TRAVEL').length === 1
    };
  }

  // 5. Run optimal Dijkstra
  const baseAdj = buildAdjacencyList();
  const optimalRoute = runDijkstraSearch(baseAdj);

  // 6. Run alternative Dijkstra (penalizing lines from optimal route)
  const candidateRoutes = [...directRoutes];
  if (optimalRoute) {
    candidateRoutes.push(optimalRoute);

    // Extract line IDs used in optimal route
    const usedLineIds = new Set();
    for (const leg of optimalRoute.legs) {
      if (leg.type === 'TRAVEL' && leg.lineId) {
        usedLineIds.add(leg.lineId);
      }
    }

    // Run Dijkstra again on penalized graph
    const penalizedAdj = buildAdjacencyList(usedLineIds);
    const alternativeRoute = runDijkstraSearch(penalizedAdj);
    if (alternativeRoute) {
      candidateRoutes.push(alternativeRoute);
    }
  }

  // 7. Deduplicate and format results
  const uniqueRoutes = [];
  const seenSignatures = new Set();

  for (const r of candidateRoutes) {
    const travelLegs = r.legs.filter(l => l.type === 'TRAVEL');
    const signature = travelLegs.map(l => l.routeId).join('->');
    const timeSig = `${signature}_${r.totalTimeMin.toFixed(2)}`;

    if (!seenSignatures.has(timeSig)) {
      seenSignatures.add(timeSig);
      uniqueRoutes.push(r);
    }
  }

  // Sort primarily by time
  uniqueRoutes.sort((a, b) => a.totalTimeMin - b.totalTimeMin);

  // Ensure we include at least one transfer option if available
  const result = [];
  let addedTransfer = false;
  
  for (const r of uniqueRoutes) {
    // If we have 2 routes and neither is a transfer, try to force a transfer route
    if (result.length === 2 && !addedTransfer) {
       const bestTransfer = uniqueRoutes.find(rt => !rt.isDirect);
       if (bestTransfer && !result.includes(bestTransfer)) {
          result.push(bestTransfer);
          addedTransfer = true;
          continue;
       }
    }
    if (!result.includes(r)) {
       result.push(r);
       if (!r.isDirect) addedTransfer = true;
    }
    if (result.length >= 3) break;
  }
  
  // Final presentation sort: Direct first, then time
  result.sort((a, b) => {
    if (a.isDirect && !b.isDirect) return -1;
    if (!a.isDirect && b.isDirect) return 1;
    return a.totalTimeMin - b.totalTimeMin;
  });

  return result;
}

module.exports = {
  findOptimalRoute,
  findAlternativeRoutes,
  haversine
};
