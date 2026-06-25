# Sistema de Ruteo de Microbuses SIG - Santa Cruz de la Sierra

Este es un proyecto Full-Stack de Sistema de Información Geográfica (SIG) y ruteo óptimo para los microbuses de la ciudad de Santa Cruz de la Sierra. La solución consta de una base de datos relacional PostgreSQL, una API REST en Node.js/Express que calcula rutas óptimas con el algoritmo de Dijkstra, y una aplicación móvil híbrida desarrollada en Flutter.

---

## Estructura del Proyecto

```text
Proyecto_1_2026/
│
├── database/                   # Base de Datos PostgreSQL
│   ├── schema.sql              # Definición de tablas, llaves foráneas e índices
│   ├── generate_seed.py        # Script Python para procesar el Excel y generar el seed
│   └── seed.sql                # Archivo SQL generado con todos los datos listos para importar
│
├── backend/                    # Servidor REST API (Node.js/Express)
│   ├── src/
│   │   ├── db.js               # Conector a PostgreSQL (compatible con pool)
│   │   ├── dijkstra.js         # Motor del algoritmo Dijkstra con transbordos y caminatas
│   │   └── index.js            # Endpoints del servidor Express y logging
│   ├── .env.example            # Plantilla de variables de entorno
│   └── package.json            # Dependencias del Backend
│
└── mobile/                     # Aplicación Híbrida Móvil (Flutter)
    ├── lib/
    │   ├── services/
    │   │   └── api_service.dart# Cliente REST para conectar la App con la API Backend
    │   ├── screens/
    │   │   └── home_screen.dart# Pantalla principal con mapa Leaflet, búsqueda e itinerario
    │   └── main.dart           # Entrada principal y definición del tema visual oscuro
    └── pubspec.yaml            # Dependencias de Flutter (flutter_map, latlong2, http)
```

---

## 1. Configuración de la Base de Datos (PostgreSQL)

### A. Despliegue en la Nube Gratis (Recomendado)
Puedes crear una base de datos PostgreSQL gratuita en segundos usando plataformas como **Supabase** o **Neon**:
1.  Crea una cuenta en [Supabase](https://supabase.com/) o [Neon](https://neon.tech/).
2.  Crea un nuevo proyecto y selecciona **PostgreSQL** como base de datos.
3.  Copia la cadena de conexión (Connection String) que te proporciona la plataforma. Se verá similar a esto:
    `postgresql://postgres:contraseña@db-hostname.supabase.co:5432/postgres` o `postgresql://user:password@ep-host.us-east-2.aws.neon.tech/neondb?sslmode=require`

### B. Creación del Esquema y Carga de Datos
1.  Entra al Editor SQL de tu panel de Supabase/Neon o conéctate usando un cliente como **pgAdmin** o **DBeaver**.
2.  Copia y ejecuta el contenido de [database/schema.sql](file:///c:/Users/migue/Desktop/sig/proyecto/Proyecto_1_2026/database/schema.sql) para crear las tablas, índices espaciales y llaves foráneas.
3.  Copia y ejecuta el contenido de [database/seed.sql](file:///c:/Users/migue/Desktop/sig/proyecto/Proyecto_1_2026/database/seed.sql) para cargar los datos geográficos de las líneas, paradas y transbordos de Santa Cruz.
    *(Nota: `seed.sql` fue generado automáticamente por [database/generate_seed.py](file:///c:/Users/migue/Desktop/sig/proyecto/Proyecto_1_2026/database/generate_seed.py) calculando las distancias geográficas reales mediante la fórmula de Haversine y escalando los datos para coincidir perfectamente con los tiempos y distancias totales de las rutas).*

---

## 2. Configuración del Backend (REST API)

El backend expone endpoints REST para que la app móvil consulte líneas, paradas cercanas y calcule la ruta óptima de un punto A a un punto B utilizando **Dijkstra**.

### Pasos para Ejecutar Localmente:
1.  Asegúrate de tener instalado **Node.js** (versión 16 o superior).
2.  Entra a la carpeta backend:
    ```bash
    cd backend
    ```
3.  Crea tu archivo de configuración `.env` copiando el ejemplo:
    ```bash
    copy .env.example .env
    ```
4.  Edita el archivo `.env` y coloca tu enlace de conexión a PostgreSQL en la variable `DATABASE_URL`.
5.  Inicia el servidor en modo desarrollo:
    ```bash
    npm run dev
    ```
    El servidor iniciará en `http://localhost:3000`.

### Despliegue Gratis en la Nube:
Puedes hospedar esta API de forma gratuita en **Render** o **Railway**:
1.  Sube el código a un repositorio de GitHub (público o privado).
2.  Crea un servicio web (Web Service) gratuito en [Render](https://render.com/).
3.  Conecta tu repositorio de GitHub.
4.  Configura las siguientes propiedades en Render:
    *   **Build Command**: `npm install`
    *   **Start Command**: `npm start`
5.  En la sección **Environment**, agrega la variable de entorno `DATABASE_URL` con el string de conexión de tu base de datos de Supabase/Neon.
6.  ¡Listo! Render te dará una URL pública (ej. `https://mi-api-micros.onrender.com`) que podrás usar en la App móvil.

---

## 3. Configuración de la App Móvil (Flutter)

La app móvil utiliza **flutter_map** (Leaflet para Flutter) con OpenStreetMap para dibujar las líneas y rumbos, detectar paradas cercanas, y mostrar paso a paso la ruta calculada por el backend.

### Pasos para Ejecutar:
1.  Asegúrate de tener instalado el SDK de **Flutter** (versión 3.0 o superior).
2.  Entra a la carpeta de la app móvil:
    ```bash
    cd mobile
    ```
3.  Abre el archivo [mobile/lib/services/api_service.dart](file:///c:/Users/migue/Desktop/sig/proyecto/Proyecto_1_2026/mobile/lib/services/api_service.dart).
4.  Si estás ejecutando el backend localmente, la URL predeterminada `http://10.0.2.2:3000/api` funcionará en el emulador de Android. Si usas un emulador de iOS, la app cambiará automáticamente a `http://localhost:3000/api`.
5.  **Si desplegaste el backend en Render**, cambia el valor de la variable `baseUrl` por tu URL pública de Render:
    ```dart
    static const String baseUrl = 'https://tu-app-en-render.onrender.com/api';
    ```
6.  Conecta un dispositivo móvil o inicia un emulador y corre la aplicación:
    ```bash
    flutter run
    ```

---

## Funcionalidades Detalladas del Sistema de Ruteo (Dijkstra)

*   **Puntos de Inicio/Fin**: Se pueden seleccionar marcando directamente cualquier punto físico en el mapa de Santa Cruz.
*   **Segmentación Multilínea**: Si la ruta requiere un transbordo (transferencia), el mapa pintará cada tramo con el color exacto correspondiente a cada línea de microbús (ej. Tramo L001 en rojo, Tramo L005 en verde), y las secciones peatonales en una línea punteada gris.
*   **Transbordos Inteligentes**: Además de usar la tabla oficial de transbordos, el algoritmo cuenta con un modo de detección de intersecciones físicas que calcula transferencias en cualquier parada en común de la ciudad, aplicando una penalización de tiempo configurable.
