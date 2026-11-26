// ============================================================
// Dirección a domicilio (sql/v80): sugerencias al escribir, «usar mi ubicación»
// y distancia «a la redonda» desde el taller con su recargo por km extra.
//
// Dos proveedores:
//  · OpenStreetMap (Photon, photon.komoot.io): gratis, sin cuenta ni clave. Es el que se usa por defecto.
//    Muchas direcciones salen solo con la calle (sin el número): se mantiene el número que escribió
//    la persona y la ubicación queda aproximada a la calle.
//  · Google Maps: solo si en Configuración → Atención a domicilio hay una clave de Google
//    (Maps JavaScript API + Places API (New) + Geocoding API). Si Google falla, se usa OpenStreetMap.
// ============================================================
(function () {
  let proveedor = null;     // 'google' | 'osm'
  let cargando = null;
  const PHOTON = 'https://photon.komoot.io';
  const BBOX_CHILE = '-76,-56,-66,-17';

  function cargarGoogle(clave) {
    return new Promise((resolve) => {
      const listo = '__autonovaMapsListo';
      const t = setTimeout(() => resolve(false), 12000);
      window[listo] = () => { clearTimeout(t); resolve(true); };
      window.gm_authFailure = () => { proveedor = 'osm'; document.dispatchEvent(new CustomEvent('maps-clave-invalida')); };
      const s = document.createElement('script');
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(clave)}&v=weekly&loading=async&language=es&region=CL&callback=${listo}`;
      s.async = true;
      s.onerror = () => { clearTimeout(t); resolve(false); };
      document.head.appendChild(s);
    });
  }
  // Deja listo el buscador (Google si hay clave y carga; si no, OpenStreetMap). Siempre resuelve true.
  function cargar(clave) {
    if (cargando) return cargando;
    cargando = (async () => {
      const ya = window.google && google.maps && google.maps.importLibrary;
      proveedor = clave && (ya || await cargarGoogle(clave)) && proveedor !== 'osm' ? 'google' : 'osm';
      return true;
    })();
    return cargando;
  }
  const disponible = () => !!proveedor;
  const usaGoogle = () => proveedor === 'google';

  // Distancia en línea recta en km, con 1 decimal (igual que _recargo_distancia en SQL)
  function distanciaKm(a, b) {
    const rad = (g) => g * Math.PI / 180;
    const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2
      + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
    return Math.round(2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h))) * 10) / 10;
  }
  // { km, radio_km, valor_km, extra_km, recargo } o null si no hay ubicación del taller
  function recargoDistancia(punto, cfg) {
    if (!punto || !cfg || cfg.lat == null || cfg.lng == null) return null;
    const km = distanciaKm({ lat: Number(cfg.lat), lng: Number(cfg.lng) }, punto);
    const radio = Math.max(0, Number(cfg.radio_km ?? 6));
    const valor = Math.max(0, Number(cfg.valor_km ?? 0));
    const extra = km > radio ? Math.ceil(Math.round((km - radio) * 10) / 10) : 0;
    return { km, radio_km: radio, valor_km: valor, extra_km: extra, recargo: Math.round(extra * valor) };
  }
  const fmtKm = (n) => Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 });
  const pesos = (n) => '$' + Math.round(Number(n) || 0).toLocaleString('es-CL');

  // Texto para el cliente: «A 8,4 km del taller: los primeros 6 km sin recargo; 3 km extra × $3.000 = $9.000 + IVA.»
  function textoRecargo(r, aproximada) {
    if (!r) return '';
    const aprox = aproximada ? ' (aprox.)' : '';
    if (!r.extra_km) return `📍 A ${fmtKm(r.km)} km${aprox} del taller: dentro de los ${fmtKm(r.radio_km)} km sin recargo por distancia.`;
    return `📍 A ${fmtKm(r.km)} km${aprox} del taller. Los primeros ${fmtKm(r.radio_km)} km no tienen recargo; `
      + `${r.extra_km} km extra × ${pesos(r.valor_km)} = ${pesos(r.recargo)} + IVA de recargo por distancia.`;
  }

  // Link para abrir la ruta en Google Maps (con coordenadas si las hay; si no, con la dirección escrita)
  function linkComoLlegar(lat, lng, direccion) {
    const destino = lat != null && lng != null ? `${lat},${lng}` : String(direccion || '');
    return destino ? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(destino)}` : '';
  }

  // ---------- OpenStreetMap (Photon) ----------
  const numeroEscrito = (texto) => { const m = String(texto || '').match(/\b(\d{1,5})\b/); return m ? m[1] : ''; };
  // Una sugerencia de Photon → { principal, secundario, direccion, lat, lng, aproximada }
  function desdePhoton(f, texto) {
    const p = f.properties || {};
    const calle = p.street || (p.type === 'street' ? p.name : '');
    const num = p.housenumber || (calle ? numeroEscrito(texto) : '');
    const calleNum = calle ? `${calle}${num ? ' ' + num : ''}` : '';
    const lugar = p.name && p.name !== calle && p.type !== 'street' ? p.name : '';
    const comuna = p.city || p.county || '';
    const principal = lugar || calleNum || p.name || '';
    const sector = p.locality || p.district || '';
    const secundario = [lugar ? calleNum : '', sector, comuna, p.state].filter(Boolean)
      .filter((x, i, a) => a.indexOf(x) === i && x !== principal).join(', ');
    return {
      principal, secundario,
      direccion: [calleNum || principal, comuna].filter(Boolean).join(', '),
      lat: f.geometry.coordinates[1], lng: f.geometry.coordinates[0],
      aproximada: !p.housenumber,
    };
  }
  async function photon(ruta) {
    const r = await fetch(PHOTON + ruta);
    if (!r.ok) throw new Error('photon ' + r.status);
    const j = await r.json();
    return (j.features || []).filter(f => (f.properties || {}).countrycode === 'CL');
  }
  async function sugerenciasOSM(texto, origen) {
    let q = `/api/?q=${encodeURIComponent(texto)}&limit=8&bbox=${BBOX_CHILE}`;
    if (origen && origen.lat != null) q += `&lat=${Number(origen.lat)}&lon=${Number(origen.lng)}`;
    const vistas = new Set();
    return (await photon(q)).map(f => desdePhoton(f, texto))
      .filter(s => s.principal && !vistas.has(s.principal + '|' + s.secundario) && vistas.add(s.principal + '|' + s.secundario))
      .slice(0, 5)
      .map(s => ({ principal: s.principal, secundario: s.secundario, elegir: async () => s }));
  }

  // ---------- Google ----------
  async function sugerenciasGoogle(texto, origen, sesion) {
    const { AutocompleteSuggestion, AutocompleteSessionToken } = await google.maps.importLibrary('places');
    if (!sesion.token) sesion.token = new AutocompleteSessionToken();
    const pet = { input: texto, sessionToken: sesion.token, includedRegionCodes: ['cl'], language: 'es', region: 'cl' };
    if (origen && origen.lat != null) {
      pet.origin = { lat: Number(origen.lat), lng: Number(origen.lng) };
      pet.locationBias = { center: pet.origin, radius: 40000 };
    }
    const { suggestions } = await AutocompleteSuggestion.fetchAutocompleteSuggestions(pet);
    return (suggestions || []).map(s => s.placePrediction).filter(Boolean).slice(0, 5).map(p => ({
      principal: p.mainText ? p.mainText.toString() : p.text.toString(),
      secundario: p.secondaryText ? p.secondaryText.toString().replace(/, Chile$/, '') : '',
      elegir: async () => {
        const place = p.toPlace();
        await place.fetchFields({ fields: ['formattedAddress', 'location'] });
        sesion.token = null;   // la sesión termina al elegir
        return { direccion: String(place.formattedAddress || p.text.toString()).replace(/, Chile$/, ''),
                 lat: place.location.lat(), lng: place.location.lng(), aproximada: false };
      },
    }));
  }
  async function geocodificarGoogle(peticion) {
    const { Geocoder } = await google.maps.importLibrary('geocoding');
    const { results } = await new Geocoder().geocode(peticion);
    const r = results && results[0];
    return r ? { direccion: r.formatted_address.replace(/, Chile$/, ''), lat: r.geometry.location.lat(), lng: r.geometry.location.lng(), aproximada: false } : null;
  }

  // Texto → { direccion, lat, lng, aproximada } (para cuando escribieron sin elegir una sugerencia)
  async function buscarDireccion(texto, origen) {
    try {
      if (usaGoogle()) return await geocodificarGoogle({ address: texto, componentRestrictions: { country: 'CL' } });
      if (proveedor === 'osm') { const s = await sugerenciasOSM(texto, origen); return s.length ? await s[0].elegir() : null; }
    } catch (e) { /* sin resultado */ }
    return null;
  }
  async function direccionDePunto(punto) {
    try {
      if (usaGoogle()) return await geocodificarGoogle({ location: punto });
      const f = (await photon(`/reverse?lat=${punto.lat}&lon=${punto.lng}`))[0];
      return f ? desdePhoton(f, '') : null;
    } catch (e) { return null; }
  }

  // Ubicación actual del celular → { direccion, lat, lng }. Lanza Error con un texto claro si no se puede.
  function miUbicacion() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) return reject(new Error('Tu navegador no permite compartir la ubicación. Escribe la dirección.'));
      navigator.geolocation.getCurrentPosition(async (pos) => {
        const punto = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        const r = await direccionDePunto(punto);
        // Con el GPS la ubicación es exacta aunque la dirección encontrada sea solo la calle
        resolve({ direccion: r ? r.direccion : '', ...punto, aproximada: false, sinNumero: !!(r && r.aproximada) });
      }, (err) => reject(new Error(err && err.code === 1
        ? 'No diste permiso para usar tu ubicación. Puedes escribir la dirección.'
        : 'No pudimos obtener tu ubicación. Escribe la dirección.')),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 });
    });
  }

  // Estilos del menú de sugerencias (una vez)
  function estilos() {
    if (document.getElementById('maps-dir-css')) return;
    const st = document.createElement('style');
    st.id = 'maps-dir-css';
    st.textContent = `
      .maps-dir-wrap { position: relative; }
      .maps-dir-lista { position: absolute; left: 0; right: 0; top: 100%; z-index: 50; margin: 2px 0 0; padding: 0; list-style: none;
        background: #fff; border: 1px solid #d0d5dd; border-radius: 8px; box-shadow: 0 6px 18px rgba(0,0,0,.12); max-height: 280px; overflow-y: auto; }
      .maps-dir-lista li { padding: 0.55rem 0.7rem; cursor: pointer; font-size: 0.9rem; line-height: 1.25; border-bottom: 1px solid #f0f1f3; }
      .maps-dir-lista li:last-child { border-bottom: 0; }
      .maps-dir-lista li:hover, .maps-dir-lista li.activo { background: #f3f6fb; }
      .maps-dir-lista li small { display: block; color: #667085; font-size: 0.78rem; }
      .maps-dir-lista .maps-dir-pie { cursor: default; text-align: right; font-size: 0.7rem; color: #98a2b3; padding: 0.3rem 0.6rem; }
      .maps-dir-lista .maps-dir-pie:hover { background: #fff; }`;
    document.head.appendChild(st);
  }

  // Conecta un <input> con sugerencias. opciones:
  //   origen: { lat, lng } para ordenar por cercanía · onElegir({ direccion, lat, lng, aproximada }) · onCambio() al editar a mano
  function conectar(input, { origen = null, onElegir = () => {}, onCambio = () => {} } = {}) {
    if (!input || input.dataset.mapsConectado) return;
    input.dataset.mapsConectado = '1';
    estilos();
    const wrap = document.createElement('div');
    wrap.className = 'maps-dir-wrap';
    input.parentNode.insertBefore(wrap, input);
    wrap.appendChild(input);
    const lista = document.createElement('ul');
    lista.className = 'maps-dir-lista';
    lista.hidden = true;
    wrap.appendChild(lista);
    input.setAttribute('autocomplete', 'off');

    const sesion = { token: null };
    let timer = null, pedido = 0, sugerencias = [], activo = -1;
    const cerrar = () => { lista.hidden = true; activo = -1; };
    const esc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;');

    async function pedir(texto) {
      if (!disponible() || texto.length < 3) { cerrar(); return; }
      const n = ++pedido;
      try {
        const lst = usaGoogle() ? await sugerenciasGoogle(texto, origen, sesion) : await sugerenciasOSM(texto, origen);
        if (n !== pedido) return;
        sugerencias = lst;
        if (!sugerencias.length) { cerrar(); return; }
        lista.innerHTML = sugerencias.map((s, i) => `<li data-i="${i}">${esc(s.principal)}${s.secundario ? `<small>${esc(s.secundario)}</small>` : ''}</li>`).join('')
          + `<li class="maps-dir-pie">${usaGoogle() ? 'con Google' : '© OpenStreetMap'}</li>`;
        activo = -1;
        lista.hidden = false;
      } catch (e) { cerrar(); }
    }

    async function elegir(i) {
      const s = sugerencias[i];
      cerrar();
      if (!s) return;
      try {
        const u = await s.elegir();
        input.value = u.direccion;
        onElegir(u);
      } catch (e) { /* sin detalle: queda como texto escrito */ }
    }

    input.addEventListener('input', () => {
      onCambio();
      clearTimeout(timer);
      const texto = input.value.trim();
      timer = setTimeout(() => pedir(texto), usaGoogle() ? 280 : 450);
    });
    input.addEventListener('keydown', (e) => {
      if (lista.hidden) return;
      const items = [...lista.querySelectorAll('li[data-i]')];
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        activo = (activo + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
        items.forEach((li, k) => li.classList.toggle('activo', k === activo));
      } else if (e.key === 'Enter' && activo >= 0) {
        e.preventDefault(); elegir(activo);
      } else if (e.key === 'Escape') cerrar();
    });
    // mousedown sin efecto: el campo no pierde el foco al tocar la lista; se elige con el click (sirve en celular)
    lista.addEventListener('mousedown', (e) => e.preventDefault());
    lista.addEventListener('click', (e) => {
      const li = e.target.closest('li[data-i]');
      if (li) elegir(Number(li.dataset.i));
    });
    input.addEventListener('blur', () => setTimeout(cerrar, 300));
  }

  window.MapsDireccion = { cargar, disponible, usaGoogle, conectar, miUbicacion, buscarDireccion, distanciaKm, recargoDistancia, textoRecargo, linkComoLlegar, fmtKm };
})();
