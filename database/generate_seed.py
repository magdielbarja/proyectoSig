import os
import pandas as pd
import numpy as np

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0  # Earth's radius in kilometers
    lat1_rad, lon1_rad, lat2_rad, lon2_rad = map(np.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    a = np.sin(dlat/2)**2 + np.cos(lat1_rad) * np.cos(lat2_rad) * np.sin(dlon/2)**2
    c = 2 * np.arcsin(np.sqrt(a))
    return R * c

def escape_str(val):
    if pd.isna(val):
        return "NULL"
    s = str(val).replace("'", "''")
    return f"'{s}'"

def main():
    xls_path = r"c:\Users\migue\Desktop\sig\proyecto\Proyecto_1_2026\Datos_Lineas\DatosLineas.xls"
    output_sql_path = r"c:\Users\migue\Desktop\sig\proyecto\Proyecto_1_2026\database\seed.sql"

    print("Reading Excel sheets...")
    df_lineas = pd.read_excel(xls_path, sheet_name='Lineas')
    df_puntos = pd.read_excel(xls_path, sheet_name='Puntos')
    df_linea_ruta = pd.read_excel(xls_path, sheet_name='LineaRuta')
    df_lineas_puntos = pd.read_excel(xls_path, sheet_name='LineasPuntos')
    df_transbordos = pd.read_excel(xls_path, sheet_name='PuntosTrasbordos')

    puntos_dict = df_puntos.set_index('IdPunto').to_dict('index')
    linea_ruta_dict = df_linea_ruta.set_index('IdLineaRuta').to_dict('index')

    print("Calculating and scaling segment distances/times...")
    # Precalculate sum of haversine distances for each route
    route_calc_dists = {}
    for r_id in df_linea_ruta['IdLineaRuta']:
        sub = df_lineas_puntos[df_lineas_puntos['IdLineaRuta'] == r_id]
        total_d = 0.0
        for _, row in sub.iterrows():
            p1_id = row['IdPunto']
            p2_id = row['IdPuntoDest']
            if p2_id != 0 and p1_id in puntos_dict and p2_id in puntos_dict:
                p1 = puntos_dict[p1_id]
                p2 = puntos_dict[p2_id]
                total_d += haversine(p1['Latitud'], p1['Longitud'], p2['Latitud'], p2['Longitud'])
        route_calc_dists[r_id] = total_d

    # Build SQL statements
    statements = []
    statements.append("-- Seed data generated from DatosLineas.xls\n")
    statements.append("BEGIN;\n")

    # 1. Insert into lineas
    statements.append("-- 1. LINEAS\n")
    for _, row in df_lineas.iterrows():
        id_linea = int(row['IdLinea'])
        nombre = escape_str(row['NombreLinea'])
        color = escape_str(row['ColorLinea'])
        imagen = escape_str(row['ImagenMicrobus'])
        fecha = escape_str(row['FechaCreacion'])
        statements.append(f"INSERT INTO lineas (id_linea, nombre_linea, color_linea, imagen_microbus, fecha_creacion) VALUES ({id_linea}, {nombre}, {color}, {imagen}, {fecha});\n")

    # 2. Insert into puntos
    statements.append("\n-- 2. PUNTOS\n")
    for _, row in df_puntos.iterrows():
        id_punto = int(row['IdPunto'])
        lat = row['Latitud']
        lon = row['Longitud']
        desc = escape_str(row['Descripcion'])
        stop = escape_str(row['Stop'])
        statements.append(f"INSERT INTO puntos (id_point, latitud, longitud, descripcion, stop) VALUES ({id_punto}, {lat}, {lon}, {desc}, {stop});\n")

    # 3. Insert into linea_ruta
    statements.append("\n-- 3. LINEA_RUTA\n")
    for _, row in df_linea_ruta.iterrows():
        id_lr = int(row['IdLineaRuta'])
        id_linea = int(row['IdLinea'])
        id_ruta = int(row['IdRuta'])
        desc = escape_str(row['Descripcion'])
        dist = row['Distancia']
        time = row['Tiempo']
        statements.append(f"INSERT INTO linea_ruta (id_linea_ruta, id_linea, id_ruta, descripcion, distancia, tiempo) VALUES ({id_lr}, {id_linea}, {id_ruta}, {desc}, {dist}, {time});\n")

    # 4. Insert into lineas_puntos
    statements.append("\n-- 4. LINEAS_PUNTOS\n")
    for _, row in df_lineas_puntos.iterrows():
        id_lp = int(row['IdLineaPunto'])
        id_lr = int(row['IdLineaRuta'])
        p1_id = int(row['IdPunto'])
        p2_id = int(row['IdPuntoDest'])
        orden = int(row['Orden'])

        # Calculate distances & times
        if p2_id == 0:
            d_scaled = 0.0
            t_scaled = 0.0
            p2_val = "NULL"
        else:
            p2_val = str(p2_id)
            if p1_id in puntos_dict and p2_id in puntos_dict:
                d_calc = haversine(puntos_dict[p1_id]['Latitud'], puntos_dict[p1_id]['Longitud'],
                                   puntos_dict[p2_id]['Latitud'], puntos_dict[p2_id]['Longitud'])
            else:
                d_calc = 0.0

            r_total_dist = linea_ruta_dict[id_lr]['Distancia']
            r_total_time = linea_ruta_dict[id_lr]['Tiempo']
            r_calc_dist = route_calc_dists[id_lr]

            if r_calc_dist > 0:
                d_scaled = (d_calc / r_calc_dist) * r_total_dist
                t_scaled = (d_calc / r_calc_dist) * r_total_time
            else:
                d_scaled = d_calc
                t_scaled = d_calc / 20.0 # fallback: 20km/h

        statements.append(f"INSERT INTO lineas_puntos (id_linea_punto, id_linea_ruta, id_punto, id_punto_dest, orden, distancia, tiempo) VALUES ({id_lp}, {id_lr}, {p1_id}, {p2_val}, {orden}, {d_scaled:.8f}, {t_scaled:.8f});\n")

    # 5. Insert into puntos_trasbordos
    statements.append("\n-- 5. PUNTOS_TRASBORDOS\n")
    for _, row in df_transbordos.iterrows():
        id_tb = int(row['IdTrasbordo'])
        p_id = int(row['IdPunto'])
        l_orig = int(row['IdLineaOrigen'])
        l_dest = int(row['IdLineaDestino'])
        penalty = float(row['PenalizacionMin'])
        statements.append(f"INSERT INTO puntos_trasbordos (id_trasbordo, id_punto, id_linea_origen, id_linea_destino, penalizacion_min) VALUES ({id_tb}, {p_id}, {l_orig}, {l_dest}, {penalty});\n")

    statements.append("\nCOMMIT;\n")

    print(f"Writing to {output_sql_path}...")
    with open(output_sql_path, 'w', encoding='utf-8') as f:
        f.writelines(statements)
    print("Seeding script successfully generated!")

if __name__ == "__main__":
    main()
