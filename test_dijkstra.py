import pandas as pd
import numpy as np
import heapq

xls_path = r'c:\Users\migue\Desktop\sig\proyecto\Proyecto_1_2026\Datos_Lineas\DatosLineas.xls'

puntos = pd.read_excel(xls_path, sheet_name='Puntos').set_index('IdPunto')
lineas = pd.read_excel(xls_path, sheet_name='Lineas').set_index('IdLinea')
linea_ruta = pd.read_excel(xls_path, sheet_name='LineaRuta').set_index('IdLineaRuta')
lineas_puntos = pd.read_excel(xls_path, sheet_name='LineasPuntos')
transbordos = pd.read_excel(xls_path, sheet_name='PuntosTrasbordos')

# 1. Calculate segment distances and times
def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0 # km
    lat1, lon1, lat2, lon2 = map(np.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = np.sin(dlat/2)**2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon/2)**2
    c = 2 * np.arcsin(np.sqrt(a))
    return R * c

# Precalculate route total calculated distances
route_calc_dists = {}
for r_id in linea_ruta.index:
    sub = lineas_puntos[lineas_puntos['IdLineaRuta'] == r_id]
    total_d = 0.0
    for idx, row in sub.iterrows():
        p1_id = row['IdPunto']
        p2_id = row['IdPuntoDest']
        if p2_id != 0:
            p1 = puntos.loc[p1_id]
            p2 = puntos.loc[p2_id]
            total_d += haversine(p1['Latitud'], p1['Longitud'], p2['Latitud'], p2['Longitud'])
    route_calc_dists[r_id] = total_d

# Compute segment distances and times scaled to match LineaRuta totals
seg_data = []
for idx, row in lineas_puntos.iterrows():
    r_id = row['IdLineaRuta']
    p1_id = row['IdPunto']
    p2_id = row['IdPuntoDest']
    
    if p2_id == 0:
        d = 0.0
        t = 0.0
    else:
        p1 = puntos.loc[p1_id]
        p2 = puntos.loc[p2_id]
        d_calc = haversine(p1['Latitud'], p1['Longitud'], p2['Latitud'], p2['Longitud'])
        
        # Scale to match LineaRuta totals
        r_total_dist = linea_ruta.loc[r_id, 'Distancia']
        r_total_time = linea_ruta.loc[r_id, 'Tiempo'] # in hours
        r_calc_dist = route_calc_dists[r_id]
        
        if r_calc_dist > 0:
            d = (d_calc / r_calc_dist) * r_total_dist
            t = (d_calc / r_calc_dist) * r_total_time
        else:
            d = d_calc
            t = d_calc / 20.0 # fallback speed 20km/h
            
    seg_data.append((d, t))

lineas_puntos['Distancia'] = [x[0] for x in seg_data]
lineas_puntos['Tiempo'] = [x[1] for x in seg_data]

# 2. Build adjacency list for Dijkstra
# Nodes in the graph: (IdPunto, IdLineaRuta)
# We also record which routes pass through each physical point to build transfer edges
point_routes = {}
for idx, row in lineas_puntos.iterrows():
    p_id = row['IdPunto']
    r_id = row['IdLineaRuta']
    point_routes.setdefault(p_id, set()).add(r_id)

adj = {}

# Travel edges (from one point to the next in the same route)
for idx, row in lineas_puntos.iterrows():
    r_id = row['IdLineaRuta']
    p1_id = row['IdPunto']
    p2_id = row['IdPuntoDest']
    t_hours = row['Tiempo']
    d_km = row['Distancia']
    
    if p2_id != 0:
        u = (p1_id, r_id)
        v = (p2_id, r_id)
        adj.setdefault(u, []).append((v, t_hours, d_km, 'TRAVEL', r_id))

# Transfer edges
# Transbordos table lists transfers from route to route at a point
for idx, row in transbordos.iterrows():
    p_id = row['IdPunto']
    r_orig = int(row['IdLineaOrigen'])  # Route ID in reality
    r_dest = int(row['IdLineaDestino']) # Route ID in reality
    penalty_min = row['PenalizacionMin']
    penalty_hours = penalty_min / 60.0
    
    # Check if both routes actually pass through p_id
    if r_orig in point_routes.get(p_id, []) and r_dest in point_routes.get(p_id, []):
        u = (p_id, r_orig)
        v = (p_id, r_dest)
        # Find destination Line ID for printing details
        dest_line_id = int(linea_ruta.loc[r_dest, 'IdLinea'])
        adj.setdefault(u, []).append((v, penalty_hours, 0.0, 'TRANSFER', dest_line_id))

print("Graph built!")
print("Number of travel nodes:", len(adj))

# Test Dijkstra from point 1 (L001) to point 300 (L016 or similar)
def find_route(start_p, end_p):
    # Virtual start node connecting to all routes passing through start_p with 0 weight
    # Virtual end node that all routes passing through end_p connect to with 0 weight
    
    # dist[(node)] = (time_hours, dist_km, parent)
    dist = {}
    pq = [] # elements: (time_hours, dist_km, node)
    
    start_routes = point_routes.get(start_p, [])
    end_routes = point_routes.get(end_p, [])
    
    if not start_routes or not end_routes:
        return None
        
    for r_id in start_routes:
        n = (start_p, r_id)
        dist[n] = (0.0, 0.0, None, None)
        heapq.heappush(pq, (0.0, 0.0, n))
        
    visited = set()
    
    destination_node = None
    min_time_to_destination = float('inf')
    
    while pq:
        t_curr, d_curr, u = heapq.heappop(pq)
        
        if u in visited:
            continue
        visited.add(u)
        
        u_p, u_r = u
        if u_p == end_p:
            if t_curr < min_time_to_destination:
                min_time_to_destination = t_curr
                destination_node = u
                break
                
        for v, t_edge, d_edge, edge_type, detail in adj.get(u, []):
            if v in visited:
                continue
            
            t_next = t_curr + t_edge
            d_next = d_curr + d_edge
            
            if v not in dist or t_next < dist[v][0]:
                dist[v] = (t_next, d_next, u, (edge_type, detail))
                heapq.heappush(pq, (t_next, d_next, v))
                
    if destination_node is None:
        return None
        
    # Reconstruct path
    path = []
    curr = destination_node
    while curr is not None:
        path.append((curr, dist[curr]))
        curr = dist[curr][2]
    path.reverse()
    return path

# Run a test path
path = find_route(1, 300)
if path:
    print("Route found!")
    for idx, (node, info) in enumerate(path):
        p_id, r_id = node
        t_hours, d_km, parent, edge_info = info
        line_name = lineas.loc[linea_ruta.loc[r_id, 'IdLinea'], 'NombreLinea']
        print(f"  Step {idx}: Pt {p_id} on Line {line_name} (Route {r_id}) | Cumulative Time: {t_hours*60:.2f} min, Dist: {d_km:.2f} km | Event: {edge_info}")
else:
    print("No route found.")
