// Inspección precompra: planes, puntos de inspección y evaluación. Usado por pages/inspecciones.html,
// pages/configuracion.html (editor de planes) y el informe público inspeccion.html.
//
// Desde v60 cada inspección guarda en `datos` la lista de puntos con que se hizo (así el informe no cambia
// si después se editan los planes):
//   "_plan"      -> { id, nombre, nivel, precio, trabajo_id }
//   "_secciones" -> [{ id, sec, pExtra, items: [{ id, t, mode, p, rol, extra }] }]
//   "<id>"       -> 'ok' | 'warn' | 'bad' | 'na'      (ítems a evaluar)
//   "<id>_txt"   -> texto libre                       (ítems de dato: códigos de falla, kilometraje…)
//   "<id>_obs" / "<id>_fotos" / "<id>_p" -> observación, fotos e importancia ajustada en este caso
//   "_obsSec"    -> { idSección: observaciones de esa sección }
//   "_obs"       -> observaciones generales
// Las inspecciones anteriores (sin "_secciones") usan INSP_CHECKLIST con claves por posición:
//   "si_ii" (estado), "si_ii_txt" (texto), "_custom" { si: [nombres] } y "c_si_ci" (ítems extra).
// NO cambiar el orden de INSP_CHECKLIST: las inspecciones antiguas dependen de él.
// Checklist anterior a los planes (solo para mostrar las inspecciones antiguas)
const INSP_CHECKLIST = [
  { sec: '💻 Electrónica y diagnóstico', pExtra: 2, items: [
    { t: 'DTC Activos (códigos de falla)', mode: 'dtc' },
    { t: 'Km Panel', mode: 'km' },
    { t: 'Km Real (verificado)', mode: 'km' },
    { t: 'Batería — voltaje y estado', mode: 'std', p: 2 },
    { t: 'Alternador — carga correcta', mode: 'std', p: 2 },
    { t: 'Luces delanteras (cortas/largas)', mode: 'std', p: 2 },
    { t: 'Luces traseras y stop', mode: 'std', p: 2 },
    { t: 'Intermitentes y luces de emergencia', mode: 'std', p: 2 },
    { t: 'Luz reversa', mode: 'std', p: 1 },
    { t: 'Luz interior / tablero', mode: 'std', p: 1 },
    { t: 'Bocina', mode: 'std', p: 2 },
    { t: 'Sensor de estacionamiento / cámara', mode: 'std', p: 1 },
    { t: 'Sistema de alarma', mode: 'std', p: 1 },
    { t: 'Radio / pantalla / conectividad', mode: 'std', p: 1 },
  ]},
  { sec: '🔧 Motor y mecánica', pExtra: 2, items: [
    { t: 'Aceite motor — nivel y color', mode: 'std', p: 3 },
    { t: 'Aceite transmisión', mode: 'std', p: 3 },
    { t: 'Líquido de frenos', mode: 'std', p: 2 },
    { t: 'Líquido refrigerante — nivel y color', mode: 'std', p: 3 },
    { t: 'Líquido dirección hidráulica', mode: 'std', p: 2 },
    { t: 'Correa de distribución — estado y km', mode: 'std', p: 3 },
    { t: 'Correa alternador / accesorios', mode: 'std', p: 2 },
    { t: 'Mangueras y juntas — sin fugas', mode: 'std', p: 2 },
    { t: 'Filtro de aire', mode: 'std', p: 1 },
    { t: 'Filtro de combustible', mode: 'std', p: 1 },
    { t: 'Sistema de escape — sin fugas ni ruidos', mode: 'std', p: 2 },
    { t: 'Radiador — sin fugas', mode: 'std', p: 3 },
    { t: 'Arranque — sin ruidos anómalos', mode: 'std', p: 2 },
    { t: 'Ralentí — estable', mode: 'std', p: 2 },
    { t: 'Humo de escape — color y cantidad', mode: 'std', p: 3 },
  ]},
  { sec: '🛑 Frenos', pExtra: 3, items: [
    { t: 'Pastillas delanteras — espesor', mode: 'std', p: 3 },
    { t: 'Pastillas traseras — espesor', mode: 'std', p: 3 },
    { t: 'Discos delanteros — sin rayaduras ni deformación', mode: 'std', p: 3 },
    { t: 'Discos traseros — sin rayaduras ni deformación', mode: 'std', p: 3 },
    { t: 'Freno de mano — efectivo', mode: 'std', p: 2 },
    { t: 'Mangueras de freno — sin fisuras', mode: 'std', p: 3 },
    { t: 'Bomba de freno', mode: 'std', p: 3 },
    { t: 'ABS — sin luz en tablero', mode: 'std', p: 3 },
  ]},
  { sec: '🏎 Suspensión y dirección', pExtra: 3, items: [
    { t: 'Amortiguadores delanteros — sin fugas', mode: 'std', p: 2 },
    { t: 'Amortiguadores traseros — sin fugas', mode: 'std', p: 2 },
    { t: 'Rótulas y terminales — holgura', mode: 'std', p: 3 },
    { t: 'Bujes y Silent block', mode: 'std', p: 2 },
    { t: 'Cremallera de dirección', mode: 'std', p: 3 },
    { t: 'Dirección — sin vibraciones ni tirones', mode: 'std', p: 3 },
    { t: 'Alineación — verificación visual', mode: 'std', p: 1 },
    { t: 'Convergencia — desgaste uniforme', mode: 'std', p: 1 },
  ]},
  { sec: '🛞 Neumáticos y ruedas', pExtra: 3, items: [
    { t: 'Neumático delantero derecho — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático delantero izquierdo — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático trasero derecho — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático trasero izquierdo — banda rodadura', mode: 'std', p: 3 },
    { t: 'Neumático de repuesto — estado', mode: 'std', p: 1 },
    { t: 'Rines — sin daños ni fisuras', mode: 'std', p: 2 },
    { t: 'Tapas de ruedas', mode: 'std', p: 1 },
  ]},
  { sec: '🚘 Carrocería y estructura', pExtra: 1, items: [
    { t: 'Capot — sin golpes ni óxido', mode: 'std', p: 1 },
    { t: 'Guardafangos delanteros', mode: 'std', p: 1 },
    { t: 'Puertas — apertura, cierre y bisagras', mode: 'std', p: 2 },
    { t: 'Techo — sin abolladuras', mode: 'std', p: 1 },
    { t: 'Parachoques delantero', mode: 'std', p: 1 },
    { t: 'Parachoques trasero', mode: 'std', p: 1 },
    { t: 'Parabrisas — sin fisuras', mode: 'std', p: 2 },
    { t: 'Vidrios laterales — sin fisuras', mode: 'std', p: 1 },
    { t: 'Luneta trasera', mode: 'std', p: 1 },
    { t: 'Pintura — color uniforme sin retoques', mode: 'std', p: 2 },
    { t: 'Corrosión u óxido en estructura', mode: 'std', p: 3 },
    { t: 'Sellos de puertas y techo', mode: 'std', p: 1 },
    { t: 'Maletero — cierre y estado interior', mode: 'std', p: 1 },
  ]},
  { sec: '🪑 Interior', pExtra: 1, items: [
    { t: 'Tapiz y asientos — estado general', mode: 'std', p: 1 },
    { t: 'Cinturones de seguridad — funcionamiento', mode: 'std', p: 3 },
    { t: 'Airbag — sin luz en tablero', mode: 'std', p: 3 },
    { t: 'Pedales — estado y respuesta', mode: 'std', p: 2 },
    { t: 'Alfombras y tapizado suelo', mode: 'std', p: 1 },
    { t: 'Elevavidrios — todos funcionan', mode: 'std', p: 1 },
    { t: 'Espejos — eléctricos y manuales', mode: 'std', p: 1 },
    { t: 'Aire acondicionado — enfría correctamente', mode: 'std', p: 2 },
    { t: 'Calefacción — funciona', mode: 'std', p: 1 },
    { t: 'Limpiaparabrisas — velocidades y agua', mode: 'std', p: 2 },
    { t: 'Sunroof / techo corredizo (si aplica)', mode: 'std', p: 1 },
  ]},
];

// ---------- Planes de inspección (v60) ----------
// Tres planes acumulativos: cada uno incluye todo lo del anterior. Nombre, precio (sin IVA), descripción y
// duración viven en el servicio del Catálogo de trabajos vinculado (taller_config.insp_planes.trabajos), así un
// cambio de precio en el catálogo o en Configuración se ve en ambos lados. Estos valores son el punto de partida.
const INSP_PLANES_BASE = [
  { id: 'esencial', nivel: 1, nombre: 'Compra Segura Esencial', precio: 45000, horas: 1,
    lema: 'Lo indispensable antes de decidir',
    descripcion: 'Revisión visual y funcional de todo el auto: documentos, luces y electrónica, testigos y medidores del panel, niveles, fugas visibles, frenos, neumáticos, carrocería e interior, lectura de códigos de falla con escáner y prueba en ruta urbana. Ideal para autos recientes o de bajo kilometraje, o para descartar entre varias opciones.' },
  { id: 'pro', nivel: 2, nombre: 'Compra Segura Pro', precio: 55000, horas: 1.5, destacado: true,
    lema: 'La más elegida',
    descripcion: 'Todo lo del Esencial, más: revisión bajo el vehículo (chasis, fugas, rótulas, homocinéticas, espirales y cremallera), medición de pastillas y discos delanteros, espesor de pintura en capot, techo y puertas, búsqueda de choques e inundación, verificación del kilometraje y del VIN, y prueba en ruta ampliada. Ideal para la mayoría de los autos usados.' },
  { id: 'total', nivel: 3, nombre: 'Compra Segura 360°', precio: 75000, horas: 2,
    lema: 'Máxima tranquilidad',
    descripcion: 'Todo lo del Pro, más: certificado de anotaciones vigentes y de multas impagas (incluidos en el valor), escáner de todos los módulos con datos en vivo y kilometraje cruzado entre módulos, prueba de batería, de humedad del líquido de frenos y de presión y gases del sistema de refrigeración (empaquetadura de culata), frenos traseros y discos medidos, pintura panel por panel, recalls y prueba en carretera con frenada de emergencia. Ideal para autos de alto valor, con más de 100.000 km o cuando hay dudas.' },
];

// Puntos de inspección. n = plan desde el que se revisa (1 Esencial, 2 Pro, 3 360°); p = importancia en el
// puntaje (3 crítico, 2 importante, 1 menor); mode 'dtc' | 'km' = dato a anotar (no se evalúa). rol marca los
// datos que usan las alertas (kilometraje del panel / verificado y códigos de falla). Los ids no cambian nunca.
const INSP_SECCIONES_BASE = [
  { id: 'doc', sec: '📄 Documentación y antecedentes', pExtra: 2, items: [
    { id: 'doc_padron', t: 'Padrón: patente, VIN y N° de motor coinciden con el vehículo', p: 3, n: 1 },
    { id: 'doc_rt', t: 'Revisión técnica y de gases vigente', p: 2, n: 1 },
    { id: 'doc_permiso', t: 'Permiso de circulación y SOAP vigentes', p: 1, n: 1 },
    { id: 'doc_llaves', t: 'Llaves y control remoto (cantidad y funcionamiento)', p: 1, n: 1 },
    { id: 'doc_vin', t: 'VIN y N° de motor sin adulteraciones (grabados originales)', p: 3, n: 2 },
    { id: 'doc_mant', t: 'Historial de mantenciones (libro o facturas)', p: 1, n: 2 },
    { id: 'doc_grabado', t: 'Patente grabada en vidrios y espejos', p: 1, n: 3 },
    { id: 'doc_anot', t: 'Certificado de anotaciones vigentes: sin prendas, embargos ni prohibiciones', p: 3, n: 3 },
    { id: 'doc_multas', t: 'Multas de tránsito impagas (certificado del Registro de Multas)', p: 2, n: 3 },
    { id: 'doc_recall', t: 'Campañas de revisión (recall) pendientes del fabricante', p: 2, n: 3 },
  ]},
  { id: 'ele', sec: '💻 Electrónica y diagnóstico', pExtra: 2, items: [
    { id: 'dtc', t: 'DTC Activos (códigos de falla)', mode: 'dtc', rol: 'dtc', n: 1 },
    { id: 'km_panel', t: 'Km Panel', mode: 'km', rol: 'km_panel', n: 1 },
    { id: 'km_real', t: 'Km Real (verificado)', mode: 'km', rol: 'km_real', n: 2 },
    { id: 'ele_testigos', t: 'Testigos del panel: se encienden al dar contacto y se apagan al arrancar', p: 3, n: 1 },
    { id: 'ele_panel', t: 'Panel de instrumentos y medidores (velocímetro, tacómetro, temperatura, combustible)', p: 2, n: 1 },
    { id: 'ele_bateria', t: 'Batería — voltaje y estado', p: 2, n: 1 },
    { id: 'ele_alternador', t: 'Alternador — carga correcta', p: 2, n: 1 },
    { id: 'ele_luces_del', t: 'Luces delanteras (cortas/largas)', p: 2, n: 1 },
    { id: 'ele_luces_tras', t: 'Luces traseras y stop', p: 2, n: 1 },
    { id: 'ele_intermitentes', t: 'Intermitentes y luces de emergencia', p: 2, n: 1 },
    { id: 'ele_reversa', t: 'Luz reversa', p: 1, n: 1 },
    { id: 'ele_luz_interior', t: 'Luz interior / tablero', p: 1, n: 1 },
    { id: 'ele_bocina', t: 'Bocina', p: 2, n: 1 },
    { id: 'ele_radio', t: 'Radio / pantalla / conectividad', p: 1, n: 1 },
    { id: 'ele_sensor', t: 'Sensor de estacionamiento / cámara', p: 1, n: 1 },
    { id: 'ele_alarma', t: 'Sistema de alarma', p: 1, n: 2 },
    { id: 'ele_cierre', t: 'Cierre centralizado', p: 1, n: 3 },
    { id: 'ele_modulos', t: 'Escáner de todos los módulos (ABS, airbag, transmisión, carrocería)', mode: 'dtc', n: 3 },
    { id: 'ele_vivo', t: 'Datos en vivo del motor (temperatura, sondas, ajustes de combustible)', p: 2, n: 3 },
    { id: 'ele_bateria_test', t: 'Batería — prueba de carga con analizador', p: 2, n: 3 },
    { id: 'ele_km_modulos', t: 'Kilometraje guardado en los módulos coincide con el panel', p: 3, n: 3 },
  ]},
  { id: 'mot', sec: '🔧 Motor y mecánica', pExtra: 2, items: [
    { id: 'mot_aceite', t: 'Aceite motor — nivel y color', p: 3, n: 1 },
    { id: 'mot_aceite_caja', t: 'Aceite transmisión', p: 3, n: 2 },
    { id: 'mot_liq_frenos', t: 'Líquido de frenos', p: 2, n: 1 },
    { id: 'mot_refrigerante', t: 'Líquido refrigerante — nivel y color', p: 3, n: 1 },
    { id: 'mot_dir_hidraulica', t: 'Líquido dirección hidráulica', p: 2, n: 1 },
    { id: 'mot_distribucion', t: 'Correa de distribución — estado y km', p: 3, n: 1 },
    { id: 'mot_correa_acc', t: 'Correa alternador / accesorios', p: 2, n: 1 },
    { id: 'mot_mangueras', t: 'Mangueras y juntas — sin fugas', p: 2, n: 1 },
    { id: 'mot_filtro_aire', t: 'Filtro de aire', p: 1, n: 1 },
    { id: 'mot_filtro_comb', t: 'Filtro de combustible', p: 1, n: 3 },
    { id: 'mot_escape', t: 'Sistema de escape — sin fugas ni ruidos', p: 2, n: 1 },
    { id: 'mot_radiador', t: 'Radiador — sin fugas', p: 3, n: 1 },
    { id: 'mot_arranque', t: 'Arranque — sin ruidos anómalos', p: 2, n: 1 },
    { id: 'mot_ralenti', t: 'Ralentí — estable', p: 2, n: 1 },
    { id: 'mot_humo', t: 'Humo de escape — color y cantidad', p: 3, n: 1 },
    { id: 'mot_tapa', t: 'Tapa de aceite sin emulsión (mayonesa)', p: 3, n: 1 },
    { id: 'mot_ruidos', t: 'Ruidos internos del motor (golpeteo, taqués, cadena)', p: 3, n: 1 },
    { id: 'mot_fugas_bajo', t: 'Fugas vistas desde abajo (cárter, retenes, caja)', p: 2, n: 2 },
    { id: 'mot_turbo', t: 'Turbo — juego y fugas (si aplica)', p: 3, n: 2 },
    { id: 'mot_soportes', t: 'Soportes de motor y caja', p: 2, n: 3 },
    { id: 'mot_bujias', t: 'Bujías y bobinas — estado', p: 2, n: 3 },
    { id: 'mot_presion_ref', t: 'Prueba de presión del sistema de refrigeración', p: 3, n: 3 },
    { id: 'mot_gases_ref', t: 'Prueba de gases de combustión en el refrigerante (empaquetadura de culata)', p: 3, n: 3 },
  ]},
  { id: 'fre', sec: '🛑 Frenos', pExtra: 3, items: [
    { id: 'fre_visual', t: 'Frenos — revisión visual a través de las llantas', p: 3, n: 1 },
    { id: 'fre_pastillas_del', t: 'Pastillas delanteras — espesor', p: 3, n: 2 },
    { id: 'fre_pastillas_tras', t: 'Pastillas traseras — espesor', p: 3, n: 3 },
    { id: 'fre_discos_del', t: 'Discos delanteros — sin rayaduras ni deformación', p: 3, n: 2 },
    { id: 'fre_discos_tras', t: 'Discos traseros — sin rayaduras ni deformación', p: 3, n: 3 },
    { id: 'fre_mano', t: 'Freno de mano — efectivo', p: 2, n: 1 },
    { id: 'fre_mangueras', t: 'Mangueras de freno — sin fisuras', p: 3, n: 2 },
    { id: 'fre_bomba', t: 'Bomba de freno', p: 3, n: 1 },
    { id: 'fre_abs', t: 'ABS — sin luz en tablero', p: 3, n: 1 },
    { id: 'fre_humedad', t: 'Líquido de frenos — prueba de humedad', p: 2, n: 3 },
    { id: 'fre_medicion', t: 'Medición de discos con pie de metro (espesor mínimo)', p: 2, n: 3 },
  ]},
  { id: 'sus', sec: '🏎 Suspensión y dirección', pExtra: 3, items: [
    { id: 'sus_amort_del', t: 'Amortiguadores delanteros — sin fugas', p: 2, n: 1 },
    { id: 'sus_amort_tras', t: 'Amortiguadores traseros — sin fugas', p: 2, n: 1 },
    { id: 'sus_rotulas', t: 'Rótulas y terminales — holgura', p: 3, n: 2 },
    { id: 'sus_bujes', t: 'Bujes y Silent block', p: 2, n: 3 },
    { id: 'sus_cremallera', t: 'Cremallera de dirección', p: 3, n: 2 },
    { id: 'sus_direccion', t: 'Dirección — sin vibraciones ni tirones', p: 3, n: 1 },
    { id: 'sus_alineacion', t: 'Alineación — verificación visual', p: 1, n: 1 },
    { id: 'sus_convergencia', t: 'Convergencia — desgaste uniforme', p: 1, n: 1 },
    { id: 'sus_espirales', t: 'Espirales y resortes — sin quiebres', p: 3, n: 2 },
    { id: 'sus_homocineticas', t: 'Homocinéticas y guardapolvos', p: 3, n: 2 },
    { id: 'sus_bieletas', t: 'Barra estabilizadora y bieletas', p: 2, n: 3 },
    { id: 'sus_rodamientos', t: 'Rodamientos de rueda — juego y ruido', p: 3, n: 3 },
  ]},
  { id: 'neu', sec: '🛞 Neumáticos y ruedas', pExtra: 3, items: [
    { id: 'neu_dd', t: 'Neumático delantero derecho — banda rodadura', p: 3, n: 1 },
    { id: 'neu_di', t: 'Neumático delantero izquierdo — banda rodadura', p: 3, n: 1 },
    { id: 'neu_td', t: 'Neumático trasero derecho — banda rodadura', p: 3, n: 1 },
    { id: 'neu_ti', t: 'Neumático trasero izquierdo — banda rodadura', p: 3, n: 1 },
    { id: 'neu_repuesto', t: 'Neumático de repuesto — estado', p: 1, n: 1 },
    { id: 'neu_rines', t: 'Rines — sin daños ni fisuras', p: 2, n: 1 },
    { id: 'neu_tapas', t: 'Tapas de ruedas', p: 1, n: 1 },
    { id: 'neu_dot', t: 'Antigüedad de los neumáticos (fecha DOT)', p: 2, n: 2 },
    { id: 'neu_herramientas', t: 'Gata, llave de ruedas y triángulos', p: 1, n: 3 },
  ]},
  { id: 'car', sec: '🚘 Carrocería y estructura', pExtra: 1, items: [
    { id: 'car_capot', t: 'Capot — sin golpes ni óxido', p: 1, n: 1 },
    { id: 'car_guardafangos', t: 'Guardafangos delanteros', p: 1, n: 1 },
    { id: 'car_puertas', t: 'Puertas — apertura, cierre y bisagras', p: 2, n: 1 },
    { id: 'car_techo', t: 'Techo — sin abolladuras', p: 1, n: 1 },
    { id: 'car_parachoques_del', t: 'Parachoques delantero', p: 1, n: 1 },
    { id: 'car_parachoques_tras', t: 'Parachoques trasero', p: 1, n: 1 },
    { id: 'car_parabrisas', t: 'Parabrisas — sin fisuras', p: 2, n: 1 },
    { id: 'car_vidrios', t: 'Vidrios laterales — sin fisuras', p: 1, n: 1 },
    { id: 'car_luneta', t: 'Luneta trasera', p: 1, n: 1 },
    { id: 'car_pintura', t: 'Pintura — color uniforme sin retoques', p: 2, n: 1 },
    { id: 'car_corrosion', t: 'Corrosión u óxido en estructura', p: 3, n: 1 },
    { id: 'car_sellos', t: 'Sellos de puertas y techo', p: 1, n: 1 },
    { id: 'car_maletero', t: 'Maletero — cierre y estado interior', p: 1, n: 1 },
    { id: 'car_separacion', t: 'Separación entre paneles pareja (sin desalineaciones)', p: 2, n: 1 },
    { id: 'car_opticos', t: 'Ópticos y focos — sin opacidad ni humedad', p: 1, n: 1 },
    { id: 'car_choque', t: 'Huellas de choque: soldaduras, pernos movidos o sellos alterados', p: 3, n: 2 },
    { id: 'car_chasis', t: 'Bajo el vehículo: chasis, largueros y piso sin reparaciones', p: 3, n: 2 },
    { id: 'car_espesor', t: 'Espesor de pintura — capot, techo y puertas', p: 2, n: 2 },
    { id: 'car_espesor_total', t: 'Espesor de pintura — todos los paneles (panel por panel)', p: 2, n: 3 },
  ]},
  { id: 'int', sec: '🪑 Interior', pExtra: 1, items: [
    { id: 'int_tapiz', t: 'Tapiz y asientos — estado general', p: 1, n: 1 },
    { id: 'int_cinturones', t: 'Cinturones de seguridad — funcionamiento', p: 3, n: 1 },
    { id: 'int_airbag', t: 'Airbag — sin luz en tablero', p: 3, n: 1 },
    { id: 'int_pedales', t: 'Pedales — estado y respuesta', p: 2, n: 1 },
    { id: 'int_alfombras', t: 'Alfombras y tapizado suelo', p: 1, n: 1 },
    { id: 'int_elevavidrios', t: 'Elevavidrios — todos funcionan', p: 1, n: 1 },
    { id: 'int_espejos', t: 'Espejos — eléctricos y manuales', p: 1, n: 1 },
    { id: 'int_aire', t: 'Aire acondicionado — enfría correctamente', p: 2, n: 1 },
    { id: 'int_calefaccion', t: 'Calefacción — funciona', p: 1, n: 1 },
    { id: 'int_limpia', t: 'Limpiaparabrisas — velocidades y agua', p: 2, n: 1 },
    { id: 'int_sunroof', t: 'Sunroof / techo corredizo (si aplica)', p: 1, n: 1 },
    { id: 'int_desgaste', t: 'Desgaste coherente con el kilometraje (volante, pomo, pedales, asiento)', p: 2, n: 1 },
    { id: 'int_olores', t: 'Olores en la cabina (humedad, quemado, combustible)', p: 2, n: 1 },
    { id: 'int_inundacion', t: 'Señales de inundación (barro u óxido bajo alfombras y en rieles de asientos)', p: 3, n: 2 },
    { id: 'int_asientos', t: 'Regulación de asientos y apoyacabezas', p: 1, n: 3 },
  ]},
  { id: 'rut', sec: '🛣 Prueba en ruta', pExtra: 2, items: [
    { id: 'rut_frio', t: 'Arranque en frío: enciende al primer intento, sin humo ni ruidos', p: 3, n: 1 },
    { id: 'rut_aceleracion', t: 'Aceleración y respuesta del motor, sin tirones ni pérdida de potencia', p: 3, n: 1 },
    { id: 'rut_caja', t: 'Caja de cambios: pasa todas las marchas suave, sin ruidos ni golpes', p: 3, n: 1 },
    { id: 'rut_embrague', t: 'Embrague: acople, patinaje y recorrido del pedal (si es manual)', p: 3, n: 1 },
    { id: 'rut_frenado', t: 'Frenado: recto, sin vibración en el pedal ni ruidos', p: 3, n: 1 },
    { id: 'rut_direccion', t: 'Dirección centrada: el auto no se va hacia un lado', p: 2, n: 1 },
    { id: 'rut_baches', t: 'Suspensión en baches y lomos de toro: sin golpes ni ruidos', p: 2, n: 1 },
    { id: 'rut_rodado', t: 'Ruido de rodado o zumbidos a velocidad', p: 2, n: 1 },
    { id: 'rut_temperatura', t: 'Temperatura del motor estable durante toda la prueba', p: 3, n: 1 },
    { id: 'rut_testigos', t: 'Ningún testigo del panel se enciende en marcha', p: 3, n: 1 },
    { id: 'rut_olores', t: 'Olores en marcha (quemado, combustible, refrigerante)', p: 2, n: 1 },
    { id: 'rut_vibraciones', t: 'Vibraciones en volante o cabina entre 60 y 100 km/h', p: 2, n: 2 },
    { id: 'rut_reversa', t: 'Marcha atrás: entra sin ruido ni golpes', p: 2, n: 2 },
    { id: 'rut_humo', t: 'Humo al acelerar a fondo', p: 3, n: 2 },
    { id: 'rut_post', t: 'Después de la prueba: sin fugas ni olores bajo el capot', p: 2, n: 2 },
    { id: 'rut_curvas', t: 'Estabilidad en curvas y cambios de pista', p: 2, n: 3 },
    { id: 'rut_carretera', t: 'Prueba en carretera a velocidad sostenida: estabilidad y ruido', p: 2, n: 3 },
    { id: 'rut_abs', t: 'Frenada fuerte: el ABS actúa y el auto no se desvía', p: 3, n: 3 },
    { id: 'rut_freno_motor', t: 'Freno motor y respuesta al reducir marchas', p: 1, n: 3 },
    { id: 'rut_asistencias', t: 'Control crucero y asistencias de manejo (si aplica)', p: 1, n: 3 },
  ]},
];

const INSP_ESTADOS = {
  ok:   { label: 'Bien',     badge: 'badge-green' },
  warn: { label: 'Atención', badge: 'badge-yellow' },
  bad:  { label: 'Malo',     badge: 'badge-red' },
  na:   { label: 'N/A',      badge: 'badge-gray' },
};

// Importancia de cada ítem en el puntaje
const INSP_IMPORTANCIA = {
  3: { label: 'Crítico',    badge: 'badge-red',    ayuda: 'seguridad o reparación costosa' },
  2: { label: 'Importante', badge: 'badge-yellow', ayuda: 'funcionamiento, exigencia legal o costo medio' },
  1: { label: 'Menor',      badge: 'badge-gray',   ayuda: 'confort o estética' },
};
const INSP_PESO_EXTRA = 2;   // ítems agregados a mano, si la sección no define otro (pExtra)
const INSP_MODOS_DATO = { dtc: 'Códigos de falla', km: 'Kilometraje', texto: 'Dato a anotar' };
const inspPesoValido = (p) => [1, 2, 3].includes(Number(p)) ? Number(p) : null;
const inspEsc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// Configuración del taller: taller_config.insp_planes = { trabajos: { idPlan: idTrabajo }, planes: { idPlan: { lema,
// destacado } }, secciones: [...] } (las secciones solo si se editaron en Configuración). Cada página la carga.
let inspPlanesTaller = {};
// Criterios de importancia anteriores a v60 (taller_config.insp_pesos: { título: 1|2|3, 'seccion:<título>': 1|2|3 }):
// se aplican al estándar de la app mientras el taller no haya guardado sus propios planes
let inspPesosTaller = {};

// Puntos vigentes (todas las secciones, con el plan desde el que se revisa cada uno)
function inspSeccionesVigentes() {
  const guardadas = inspPlanesTaller && Array.isArray(inspPlanesTaller.secciones) && inspPlanesTaller.secciones.length
    ? inspPlanesTaller.secciones : null;
  if (guardadas) return JSON.parse(JSON.stringify(guardadas));
  const pesos = inspPesosTaller || {};
  return INSP_SECCIONES_BASE.map(s => ({
    ...s,
    pExtra: inspPesoValido(pesos['seccion:' + s.sec]) || s.pExtra,
    items: s.items.map(it => (it.mode ? { ...it } : { ...it, p: inspPesoValido(pesos[it.t]) || it.p })),
  }));
}

// Planes vigentes con su nombre, precio, descripción y duración desde el catálogo (trabajos: filas de `trabajos`)
function inspPlanesVigentes(trabajos, valorHora) {
  const cfg = inspPlanesTaller || {};
  const vinculos = cfg.trabajos || {}, extras = cfg.planes || {};
  return INSP_PLANES_BASE.map(base => {
    const trabajoId = vinculos[base.id] || null;
    const t = trabajoId ? (trabajos || []).find(x => x.id === trabajoId) : null;
    const ex = extras[base.id] || {};
    const precioCat = t && typeof precioNetoTrabajo === 'function' ? precioNetoTrabajo(t, valorHora) : null;
    return {
      ...base,
      lema: ex.lema != null ? ex.lema : base.lema,
      destacado: ex.destacado != null ? !!ex.destacado : !!base.destacado,
      nombre: (t && t.nombre) || base.nombre,
      descripcion: t ? (t.descripcion || '') : base.descripcion,
      horas: t && Number(t.horas_estimadas) > 0 ? Number(t.horas_estimadas) : base.horas,
      precio: precioCat != null ? precioCat : base.precio,
      trabajo_id: t ? t.id : null,
      trabajo_activo: t ? t.activo !== false : null,
      vinculo: t ? 'ok' : (trabajoId ? 'perdido' : 'sin'),
    };
  });
}

// Puntos que revisa un plan (nivel 1, 2 o 3): las secciones con sus ítems incluidos
function inspChecklistDePlan(nivel, secciones) {
  return (secciones || inspSeccionesVigentes()).map(s => ({
    id: s.id, sec: s.sec, pExtra: inspPesoValido(s.pExtra) || INSP_PESO_EXTRA,
    items: (s.items || []).filter(it => (Number(it.n) || 1) <= nivel).map(it => {
      const item = { id: it.id, t: it.t, mode: it.mode || 'std' };
      if (item.mode === 'std') item.p = inspPesoValido(it.p) || 2;
      if (it.rol) item.rol = it.rol;
      return item;
    }),
  })).filter(s => s.items.length);
}
function inspContarPuntos(nivel, secciones) {
  return inspChecklistDePlan(nivel, secciones).reduce((n, s) => n + s.items.length, 0);
}
// Duración en texto: 1.5 → "1 h 30 min"
function inspFmtHoras(h) {
  const min = Math.round(Number(h || 0) * 60);
  if (!min) return '';
  const hh = Math.floor(min / 60), mm = min % 60;
  return [hh ? `${hh} h` : '', mm ? `${mm} min` : ''].filter(Boolean).join(' ');
}
// Id nuevo para un punto o sección agregados (nunca se reutiliza)
function inspNuevoId(prefijo) {
  return (prefijo || 'u') + Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
}

const INSP_NIVELES = {
  recomendada:    { label: 'Recomendada',                  visual: 'ok' },
  observaciones:  { label: 'Recomendada con observaciones', visual: 'warn' },
  precaucion:     { label: 'Con precaución',               visual: 'warn' },
  no_recomendada: { label: 'No recomendada',               visual: 'bad' },
};

// Etiqueta de importancia para mostrar junto al ítem (crítico e importante; los menores no llevan)
function inspBadgeImportancia(p) {
  const imp = INSP_IMPORTANCIA[p];
  if (!imp || p < 2) return '';
  return ` <span class="badge ${imp.badge}" title="${imp.ayuda}" style="font-size:0.68rem;">${imp.label}</span>`;
}

// Texto libre de un ítem de dato (compatible con los datos migrados)
function inspTexto(datos, k) {
  return datos[k + '_txt'] || datos[k + '_dtc'] || datos[k + '_km'] || '';
}

// Estructura de una inspección: { id, sec, pExtra, items: [{ k, t, mode, p, rol, extra }] } por sección.
// La guardada en la inspección (v60) o, en las antiguas, el checklist fijo con claves por posición.
const INSP_ROL_ANTIGUO = { 'DTC Activos (códigos de falla)': 'dtc', 'Km Panel': 'km_panel', 'Km Real (verificado)': 'km_real' };
function inspEstructura(datos) {
  datos = datos || {};
  if (Array.isArray(datos._secciones)) {
    return datos._secciones.map(s => ({
      id: s.id, sec: s.sec, pExtra: inspPesoValido(s.pExtra) || INSP_PESO_EXTRA,
      items: (s.items || []).map(it => ({ k: it.id, t: it.t, mode: it.mode || 'std', p: inspPesoValido(it.p) || 2, rol: it.rol || '', extra: !!it.extra })),
    }));
  }
  return INSP_CHECKLIST.map((sec, si) => ({
    id: 'L' + si, sec: sec.sec, pExtra: sec.pExtra || INSP_PESO_EXTRA,
    items: [
      ...sec.items.map((it, ii) => ({ k: si + '_' + ii, t: it.t, mode: it.mode, p: it.p || 2, rol: INSP_ROL_ANTIGUO[it.t] || '', extra: false })),
      ...((datos._custom && datos._custom[si]) || []).map((nombre, ci) => ({ k: 'c_' + si + '_' + ci, t: nombre, mode: 'std', p: sec.pExtra || INSP_PESO_EXTRA, extra: true })),
    ],
  }));
}

// Todos los ítems con estado: { k, t, p, si, v }. La importancia es la ajustada en este caso (datos[k_p]) o la del punto.
function inspItemsEvaluables(datos) {
  const items = [];
  inspEstructura(datos).forEach((sec, si) => {
    sec.items.forEach(it => {
      if (it.mode !== 'std') return;
      items.push({ k: it.k, t: it.t, p: inspPesoValido(datos[it.k + '_p']) || it.p, si, v: datos[it.k] || '' });
    });
  });
  return items;
}

// Al terminar la inspección se guarda la importancia usada en cada hallazgo (atención/malo)
function inspFijarPesos(datos) {
  const copia = { ...datos };
  inspItemsEvaluables(datos).forEach(it => { if (it.v === 'warn' || it.v === 'bad') copia[it.k + '_p'] = it.p; });
  return copia;
}

const inspNumeroKm = (txt) => { const n = String(txt || '').replace(/[^\d]/g, ''); return n ? Number(n) : null; };
const inspMiles = (n) => Number(n).toLocaleString('es-CL');

// Evaluación de la inspección:
//  1. Puntaje ponderado: cada ítem pesa según su importancia (crítico ×3, importante ×2, menor ×1);
//     «Bien» vale 100, «Atención» 50 y «Malo» 0. N/A no cuenta.
//  2. Reglas que limitan la recomendación aunque el promedio sea alto:
//       · 2 o más fallas críticas, kilometraje que no coincide o puntaje < 50  → No recomendada (máx. 49)
//       · 1 falla crítica, códigos de falla activos, 3+ importantes malos o puntaje < 70 → Con precaución (máx. 69)
//       · algún crítico «Atención», algún importante «Malo» o puntaje < 85          → Con observaciones (máx. 84)
//       · si no                                                                 → Recomendada
// Devuelve contadores, score final, recomendación (con motivos) y el detalle en `evaluacion`.
function inspCalcular(datos) {
  let ok = 0, warn = 0, bad = 0, na = 0, total = 0, sumaPesos = 0, sumaPuntos = 0;
  const criticosMalos = [], criticosAtencion = [], importantesMalos = [], importantesAtencion = [];
  const estructura = inspEstructura(datos);
  const secciones = estructura.map(s => ({ sec: s.sec, pesos: 0, puntos: 0, malos: 0, atencion: 0, criticos: 0 }));
  inspItemsEvaluables(datos).forEach(it => {
    total++;
    if (it.v === 'na') { na++; return; }
    if (it.v !== 'ok' && it.v !== 'warn' && it.v !== 'bad') return;
    const puntos = it.v === 'ok' ? 100 : (it.v === 'warn' ? 50 : 0);
    if (it.v === 'ok') ok++; else if (it.v === 'warn') warn++; else bad++;
    sumaPesos += it.p; sumaPuntos += it.p * puntos;
    const s = secciones[it.si];
    s.pesos += it.p; s.puntos += it.p * puntos;
    if (it.v === 'bad') s.malos++;
    if (it.v === 'warn') s.atencion++;
    if (it.p >= 3 && it.v === 'bad') { criticosMalos.push(it.t); s.criticos++; }
    if (it.p >= 3 && it.v === 'warn') criticosAtencion.push(it.t);
    if (it.p === 2 && it.v === 'bad') importantesMalos.push(it.t);
    if (it.p === 2 && it.v === 'warn') importantesAtencion.push(it.t);
  });
  const scoreBase = sumaPesos > 0 ? Math.round(sumaPuntos / sumaPesos) : 0;

  // Señales que no son de un ítem: kilometraje y códigos de falla
  const alertas = [];
  const todos = estructura.flatMap(s => s.items);
  const textoRol = (rol) => { const it = todos.find(x => x.rol === rol); return it ? inspTexto(datos, it.k) : ''; };
  const kmPanel = inspNumeroKm(textoRol('km_panel'));
  const kmReal = inspNumeroKm(textoRol('km_real'));
  if (kmPanel && kmReal && Math.abs(kmReal - kmPanel) > Math.max(2000, kmPanel * 0.05)) {
    alertas.push({ tipo: 'km', texto: `El kilometraje del panel (${inspMiles(kmPanel)} km) no coincide con el verificado (${inspMiles(kmReal)} km): posible adulteración.` });
  }
  // Códigos de falla de cualquier dato de escáner (motor y demás módulos)
  const dtc = todos.filter(it => it.mode === 'dtc' || it.rol === 'dtc').map(it => inspTexto(datos, it.k)).join(' ').toUpperCase();
  const codigos = [...new Set(dtc.match(/\b[PBCU][0-9][0-9A-F]{3}\b/g) || [])];
  if (codigos.length) alertas.push({ tipo: 'dtc', texto: `Códigos de falla activos: ${codigos.join(', ')}.` });

  let nivel;
  if (criticosMalos.length >= 2 || alertas.some(a => a.tipo === 'km') || scoreBase < 50) nivel = 'no_recomendada';
  else if (criticosMalos.length === 1 || alertas.some(a => a.tipo === 'dtc') || importantesMalos.length >= 3 || scoreBase < 70) nivel = 'precaucion';
  else if (scoreBase < 85 || criticosAtencion.length || importantesMalos.length) nivel = 'observaciones';
  else nivel = 'recomendada';
  // El número nunca contradice la recomendación (p. ej. no puede salir 92/100 y «No recomendada»)
  const score = Math.min(scoreBase, { no_recomendada: 49, precaucion: 69, observaciones: 84, recomendada: 100 }[nivel]);

  const motivos = [];
  if (criticosMalos.length) motivos.push(`Falla en ${criticosMalos.length > 1 ? 'componentes críticos' : 'componente crítico'}: ${criticosMalos.join('; ')}.`);
  alertas.forEach(a => motivos.push(a.texto));
  // Lo que no impide la compra pero conviene reparar o revisar (sirve para negociar el precio)
  const revisar = [...criticosAtencion, ...importantesMalos, ...importantesAtencion];
  const base = {
    recomendada: 'Buen estado general. Se recomienda la compra.',
    observaciones: 'Buen estado con observaciones. Se recomienda la compra, negociando el precio según las reparaciones indicadas.',
    precaucion: 'Se recomienda precaución: hay fallas que deben repararse antes de usar el vehículo. Evalúe el costo de las reparaciones antes de decidir.',
    no_recomendada: 'NO se recomienda la compra en el estado actual, salvo que se reparen las fallas indicadas y se ajuste el precio.',
  }[nivel];
  const rec = base + (motivos.length ? ` Motivos: ${motivos.join(' ')}` : '') + (revisar.length ? ` Reparar o revisar: ${revisar.join('; ')}.` : '');
  const visual = INSP_NIVELES[nivel].visual;

  const evaluacion = {
    metodo: 2, scoreBase, score, nivel, visual, criticosMalos, criticosAtencion, importantesMalos, importantesAtencion, alertas,
    secciones: secciones.filter(s => s.pesos > 0).map(s => ({ sec: s.sec, score: Math.round(s.puntos / s.pesos), malos: s.malos, atencion: s.atencion, criticos: s.criticos })),
  };
  return { ok, warn, bad, na, total, score, rec, nivel: visual, evaluacion };
}

// Color del puntaje de una inspección guardada (las antiguas usan los umbrales de antes)
function inspNivelDe(registro) {
  const e = registro && registro.datos && registro.datos._eval;
  if (e && e.visual) return e.visual;
  const s = Number(registro && registro.score);
  return s >= 90 ? 'ok' : (s >= 60 ? 'warn' : 'bad');
}

// Resumen de la evaluación (nivel, alertas, fallas críticas y puntaje por sección). Solo inspecciones nuevas.
function inspRenderResumen(datos) {
  const e = datos && datos._eval;
  if (!e || e.metodo !== 2) return '';
  const color = { ok: '#1b6e3c', warn: '#92600a', bad: '#a93b33' }[e.visual] || '#333';
  const lista = (titulo, items, estilo) => items.length
    ? `<div style="margin:0.4rem 0;"><strong style="${estilo}">${titulo}</strong><ul style="margin:0.2rem 0 0; padding-left:1.2rem;">${items.map(t => `<li>${inspEsc(t)}</li>`).join('')}</ul></div>` : '';
  const filas = (e.secciones || []).map(s => {
    // Una sección con falla en un componente crítico sale en rojo aunque su promedio sea alto
    const c = s.criticos ? '#a93b33' : (s.score >= 85 ? '#1b6e3c' : (s.score >= 60 ? '#92600a' : '#a93b33'));
    return `<tr><td>${inspEsc(s.sec)}${s.criticos ? ' ⛔' : ''}</td><td style="text-align:center; font-weight:700; color:${c};">${s.score}</td><td style="text-align:center;">${s.malos || '–'}</td><td style="text-align:center;">${s.atencion || '–'}</td></tr>`;
  }).join('');
  return `
    <div class="insp-resumen" style="border:1px solid var(--color-border); border-left:4px solid ${color}; border-radius:8px; padding:0.75rem 1rem; margin:0.75rem 0 1rem;">
      <div style="font-weight:700; color:${color}; font-size:1.05rem;">${(INSP_NIVELES[e.nivel] || {}).label || ''}</div>
      ${lista('🚨 Alertas', (e.alertas || []).map(a => a.texto), 'color:#a93b33;')}
      ${lista('⛔ Fallas en componentes críticos', e.criticosMalos || [], 'color:#a93b33;')}
      ${lista('⚠ Componentes críticos que requieren atención', e.criticosAtencion || [], 'color:#92600a;')}
      ${lista('🔧 Para reparar o revisar (componentes importantes)', [...(e.importantesMalos || []).map(t => `${t} — malo`), ...(e.importantesAtencion || []).map(t => `${t} — atención`)], 'color:#5b4a12;')}
      ${filas ? `<table style="margin-top:0.5rem;"><thead><tr><th style="text-align:left;">Sección</th><th>Puntaje</th><th>Malos</th><th>Atención</th></tr></thead><tbody>${filas}</tbody></table>` : ''}
      <p style="font-size:0.78rem; color:var(--color-text-muted); margin:0.5rem 0 0;">
        Cómo se calcula: cada ítem pesa según su importancia (crítico ×3, importante ×2, menor ×1); «Atención» vale la mitad
        y «Malo» cero. Una falla en un componente crítico, un kilometraje que no coincide o códigos de falla activos limitan
        la recomendación aunque el promedio general sea alto.${e.score !== e.scoreBase ? ` Promedio ponderado sin límites: ${e.scoreBase}/100.` : ''}
      </p>
    </div>`;
}

// Observación + fotos de un ítem (obligatorias con atención/malo, opcionales con «Bien» y en los datos)
function inspEvidencia(datos, k) {
  const obs = datos[k + '_obs'];
  const fotos = datos[k + '_fotos'] || [];
  if (!obs && !fotos.length) return '';
  let html = '';
  if (obs) html += `<div style="font-size:0.82rem; color:var(--color-text-muted); margin-top:3px;">${inspEsc(obs)}</div>`;
  if (fotos.length) {
    html += `<div class="fotos-grid" style="margin-top:5px;">` +
      fotos.map(u => `<div class="foto-item"><a href="${inspEsc(u)}" target="_blank"><img src="${inspEsc(u)}" /></a></div>`).join('') +
      `</div>`;
  }
  return html;
}

// Render de solo lectura del checklist respondido (detalle interno e informe público). Muestra solo ítems con
// respuesta o texto, las observaciones de cada sección y, en los críticos con atención/malo, su etiqueta.
function inspRenderDetalle(datos) {
  datos = datos || {};
  const etiquetaCritico = (p, v) => (p >= 3 && (v === 'warn' || v === 'bad')) ? inspBadgeImportancia(3) : '';
  const obsSec = datos._obsSec || {};
  return inspEstructura(datos).map(sec => {
    const filas = [];
    sec.items.forEach(it => {
      const k = it.k;
      const nombre = inspEsc(it.t) + (it.extra ? ' <span class="badge">extra</span>' : '');
      if (it.mode === 'std') {
        const v = datos[k];
        if (!v || !INSP_ESTADOS[v]) return;
        filas.push(`<tr><td>${nombre}${etiquetaCritico(inspPesoValido(datos[k + '_p']) || it.p, v)}${v !== 'na' ? inspEvidencia(datos, k) : ''}</td><td><span class="badge ${INSP_ESTADOS[v].badge}">${INSP_ESTADOS[v].label}</span></td></tr>`);
      } else {
        const txt = inspTexto(datos, k);
        const fotos = inspEvidencia({ [k + '_fotos']: datos[k + '_fotos'] }, k);
        if (!txt && !fotos) return;
        filas.push(`<tr><td>${nombre}${fotos}</td><td>${inspEsc(txt) || '–'}</td></tr>`);
      }
    });
    const obs = String(obsSec[sec.id] || '').trim();
    if (obs) filas.push(`<tr><td colspan="2" style="background:#f6f7f9;"><strong>Observaciones de la sección:</strong> ${inspEsc(obs).replace(/\n/g, '<br>')}</td></tr>`);
    if (!filas.length) return '';
    return `<h3>${inspEsc(sec.sec)}</h3><table><tbody>${filas.join('')}</tbody></table>`;
  }).join('');
}

// Plan con que se hizo una inspección (solo las de v60 en adelante)
function inspPlanDe(datos) {
  const p = datos && datos._plan;
  return p && p.nombre ? p : null;
}

// Folleto comercial de los planes (para imprimir o enviar en PDF): planes con su precio + IVA, puntos, duración
// y qué revisa cada uno, sección por sección.
function inspFolletoPlanesHtml(planes, secciones, taller) {
  taller = taller || {};
  const moneda = (n) => (typeof fmtMoneda === 'function' ? fmtMoneda(n) : '$' + inspMiles(n));
  const listas = planes.map(p => inspChecklistDePlan(p.nivel, secciones));
  const tarjetas = planes.map((p, i) => `
    <div style="flex:1 1 0; min-width:0; border:${p.destacado ? '2px solid #e1341e' : '1px solid #d9dde3'}; border-radius:10px; padding:12px; position:relative;">
      ${p.destacado ? `<div style="position:absolute; top:-10px; right:10px; background:#e1341e; color:#fff; font-size:10px; font-weight:700; padding:2px 8px; border-radius:10px;">${inspEsc(p.lema || 'Recomendado')}</div>` : ''}
      <div style="font-weight:800; font-size:15px;">${inspEsc(p.nombre)}</div>
      ${!p.destacado && p.lema ? `<div style="font-size:11px; color:#6a727f;">${inspEsc(p.lema)}</div>` : ''}
      <div style="font-size:22px; font-weight:800; margin:6px 0 0;">${moneda(p.precio)} <span style="font-size:12px; font-weight:600; color:#6a727f;">+ IVA</span></div>
      <div style="font-size:12px; font-weight:700; margin:6px 0;">${listas[i].reduce((n, s) => n + s.items.length, 0)} puntos${p.horas ? ` · ${inspFmtHoras(p.horas)} aprox.` : ''}</div>
      <div style="font-size:11px; line-height:1.4;">${inspEsc(p.descripcion)}</div>
    </div>`).join('');
  return `
    <div class="print-brand">
      <img src="${taller.logo || '../assets/img/logo.png'}" alt="" onerror="this.style.display='none'" />
      <span class="print-brand-name">${inspEsc(taller.nombre || '')}</span>
    </div>
    <h2 style="margin:6px 0 2px;">Inspección precompra: compra con seguridad</h2>
    <p style="margin:0 0 12px; font-size:12px; color:#6a727f;">Revisamos el auto que quieres comprar y te entregamos un informe con puntaje, fotos, fallas críticas
      y una recomendación clara. Todos los planes incluyen escáner, prueba en ruta e informe digital.</p>
    <div style="display:flex; gap:10px; align-items:stretch; margin-bottom:14px;">${tarjetas}</div>
    ${inspTablaComparativaHtml(planes, secciones, { fuente: '11px' })}
    <p style="font-size:11px; color:#6a727f; margin-top:10px;">${inspEsc([taller.direccion, taller.telefono, taller.email].filter(Boolean).join(' · '))}</p>`;
}

// Tabla comparativa de los planes: cada punto con ✓ en los planes que lo revisan y, al final, el total de puntos
function inspTablaComparativaHtml(planes, secciones, opciones) {
  opciones = opciones || {};
  const incluido = (it, p) => (Number(it.n) || 1) <= p.nivel;
  const filas = secciones.filter(s => (s.items || []).length).map(s => {
    const cab = `<tr class="tc-sec"><td colspan="${planes.length + 1}" style="background:#f2f4f7; font-weight:700; padding:5px 6px;">${inspEsc(s.sec)}</td></tr>`;
    const items = (s.items || []).map(it => `<tr><td style="padding:3px 6px;">${inspEsc(it.t)}</td>${planes.map(p => `<td style="text-align:center; padding:3px 6px; color:${incluido(it, p) ? '#1b6e3c' : '#b5bac2'}; font-weight:700;">${incluido(it, p) ? '✓' : '—'}</td>`).join('')}</tr>`).join('');
    return cab + items;
  }).join('');
  const totales = `<tr style="font-weight:700; border-top:2px solid #d9dde3;"><td style="padding:5px 6px;">Total de puntos</td>${planes.map(p => `<td style="text-align:center; padding:5px 6px;">${inspContarPuntos(p.nivel, secciones)}</td>`).join('')}</tr>`;
  return `
    <table class="tabla-comparativa" style="width:100%; border-collapse:collapse; font-size:${opciones.fuente || '0.82rem'};">
      <thead><tr><th style="text-align:left; padding:4px 6px;">Qué revisamos</th>${planes.map(p => `<th style="padding:4px 6px; text-align:center;">${inspEsc(p.nombre)}</th>`).join('')}</tr></thead>
      <tbody>${filas}${totales}</tbody>
    </table>`;
}

// Nombre corto de cada plan, sin las palabras que comparten todos ("Compra Segura Pro" → "Pro")
function inspNombresCortos(planes) {
  const palabras = planes.map(p => String(p.nombre || '').trim().split(/\s+/));
  let comun = 0;
  while (palabras.length > 1 && palabras.every(w => w.length > comun + 1 && w[comun] === palabras[0][comun])) comun++;
  return palabras.map((w, i) => w.slice(comun).join(' ') || planes[i].nombre || `Plan ${i + 1}`);
}
