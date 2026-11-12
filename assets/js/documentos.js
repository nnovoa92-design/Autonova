// Piezas compartidas de Cotizaciones, Diagnósticos y Órdenes de trabajo: el editor para agregar ítems y el cuadro
// de cliente y vehículo. Las tres pantallas usan exactamente lo mismo, así una mejora llega a todas.
// Requiere layout.js (setupCombobox, datosManoObra, consultarPatente, formatos de RUT/teléfono/patente…).

// ---------- Ventana con formulario (para «+ Nuevo») ----------
// Devuelve { fondo, cerrar(), error(texto) }. onGuardar recibe la ventana.
function ventanaFormulario(titulo, cuerpoHtml, onGuardar) {
  const fondo = document.createElement('div');
  fondo.className = 'modal-backdrop abierto';
  fondo.style.zIndex = '210';
  fondo.innerHTML = `
    <div class="modal" role="dialog" aria-modal="true">
      <h3>${htmlSeguro(titulo)}</h3>
      ${cuerpoHtml}
      <p class="error-message vf-error"></p>
      <div class="modal-acciones">
        <button type="button" class="vf-guardar">Guardar</button>
        <button type="button" class="btn-secondary vf-cancelar">Cancelar</button>
      </div>
    </div>`;
  document.body.appendChild(fondo);
  const v = {
    fondo,
    cerrar: () => fondo.remove(),
    error: (t) => { fondo.querySelector('.vf-error').textContent = t; },
    valor: (sel) => { const e = fondo.querySelector(sel); return e && String(e.value).trim() ? String(e.value).trim() : null; },
  };
  fondo.querySelector('.vf-cancelar').addEventListener('click', v.cerrar);
  fondo.addEventListener('click', (e) => { if (e.target === fondo) v.cerrar(); });
  fondo.querySelector('.vf-guardar').addEventListener('click', async (e) => {
    e.target.disabled = true;
    try { await onGuardar(v); } finally { e.target.disabled = false; }
  });
  const primero = fondo.querySelector('input, select, textarea');
  if (primero) primero.focus();
  return v;
}

// Insumo de un trabajo del catálogo → repuesto del inventario con nombre parecido (para su precio de venta)
function buscarEnInventario(repuestos, desc) {
  const d = String(desc || '').toLowerCase();
  const r = (repuestos || []).find(x => {
    const n = String(x.nombre || '').toLowerCase();
    return n && (d.includes(n) || n.includes(d));
  });
  return r ? { repuesto_id: r.id, precio: Number(r.precio_venta || 0) } : { repuesto_id: null, precio: 0 };
}

const etiquetaTrabajoCatalogo = (t) => `${t.nombre}${Number(t.horas_estimadas) > 0 ? ` (${fmtNumItem(t.horas_estimadas)} h)` : ''}`;
const etiquetaRepuestoInventario = (r) => `${r.sku ? r.sku + ' · ' : ''}${r.nombre} (stock: ${fmtNumItem(r.stock_actual ?? 0)})`;

// ---------- Editor para agregar ítems ----------
//   contenedor: dónde se dibuja · trabajos / repuestos: arreglos del catálogo (se actualizan en sitio)
//   valorHora(): valor hora vigente · conStock: avisa si el repuesto no alcanza (OT, que descuenta stock)
//   onAgregar(lineas, info): la pantalla agrega las líneas a su lista o las guarda. info = { trabajo } o
//     { repuesto, cantidad }. Si devuelve false, el formulario no se limpia.
// Devuelve { recargar() } para volver a llenar las listas cuando cambia el catálogo.
function crearEditorItems({ contenedor, trabajos, repuestos, valorHora, conStock = false, onAgregar }) {
  contenedor.innerHTML = `
    <div class="form-row editor-items" style="align-items:end;">
      <div class="form-group">
        <label for="item-tipo">Tipo de ítem</label>
        <select id="item-tipo">
          <option value="mano_obra">Trabajo del catálogo (carga insumos)</option>
          <option value="repuesto">Repuesto del inventario</option>
          <option value="insumo_taller">Insumo de taller (libre)</option>
          <option value="insumo_vehiculo">Insumo de vehículo (libre)</option>
          <option value="otro">Otro (libre)</option>
        </select>
      </div>
      <div class="form-group" id="grupo-trabajo">
        <label for="trabajo-buscar">Trabajo del catálogo</label>
        <div class="combobox-wrap">
          <div class="select-con-boton">
            <input type="text" id="trabajo-buscar" placeholder="Escribe para buscar..." autocomplete="off" />
            <button type="button" class="btn-secondary btn-mini" id="nuevo-trabajo-btn" title="Crear un trabajo nuevo en el catálogo">+ Nuevo</button>
          </div>
          <div class="combobox-lista" id="trabajo-lista" style="display:none;"></div>
        </div>
        <select id="item-trabajo" style="display:none;"></select>
      </div>
      <div class="form-group" id="grupo-repuesto" style="display:none;">
        <label for="repuesto-buscar">Repuesto</label>
        <div class="combobox-wrap">
          <div class="select-con-boton">
            <input type="text" id="repuesto-buscar" placeholder="Escribe para buscar..." autocomplete="off" />
            <button type="button" class="btn-secondary btn-mini" id="nuevo-repuesto-btn" title="Crear un repuesto nuevo en el inventario">+ Nuevo</button>
          </div>
          <div class="combobox-lista" id="repuesto-lista" style="display:none;"></div>
        </div>
        <select id="item-repuesto" style="display:none;"></select>
      </div>
      <div class="form-group" id="grupo-descripcion" style="display:none;">
        <label for="item-descripcion">Descripción</label>
        <input type="text" id="item-descripcion" />
      </div>
      <div class="form-group" id="grupo-tipo-otro" style="display:none; max-width:160px;">
        <label for="item-tipo-otro">Clasificar como</label>
        <select id="item-tipo-otro">
          <option value="">Otro</option>
          <option value="repuesto">Repuesto</option>
          <option value="trabajo">Trabajo externo</option>
          <option value="mano_obra">Mano de obra</option>
          <option value="insumo">Insumo</option>
        </select>
      </div>
      <div class="form-group" style="max-width:110px;">
        <label for="item-cantidad" id="item-cantidad-label">Cantidad</label>
        <input type="number" id="item-cantidad" value="1" min="0" step="0.25" />
      </div>
      <div class="form-group" id="grupo-pct" style="display:none; max-width:180px;">
        <label for="item-pct">Se usa: <strong id="item-pct-label">100%</strong> de cada unidad</label>
        <input type="range" id="item-pct" min="5" max="100" step="5" value="100" style="padding:0;" />
      </div>
      <div class="form-group" id="grupo-horas-trabajo" style="display:none; max-width:140px;">
        <label for="item-horas">Horas por trabajo</label>
        <input type="number" id="item-horas" min="0" step="any" />
      </div>
      <div class="form-group" id="grupo-precio" style="max-width:150px;">
        <label for="item-precio">Precio unitario</label>
        <input type="number" id="item-precio" min="0" step="1" />
      </div>
      <div class="form-group" style="flex:0;">
        <button type="button" id="agregar-item-btn">Agregar</button>
      </div>
    </div>
    <p id="item-preview" style="color:var(--color-text-muted); font-weight:600; margin:0.4rem 0 0;"></p>
    <p class="error-message" id="item-error"></p>`;

  const $ = (id) => document.getElementById(id);
  const error = (t) => { $('item-error').textContent = t || ''; };
  const vh = () => Number(valorHora()) || 0;
  const trabajoElegido = () => trabajos.find(x => x.id === $('item-trabajo').value);
  const repuestoElegido = () => repuestos.find(x => x.id === $('item-repuesto').value);

  function poblar() {
    const selT = $('item-trabajo'), selR = $('item-repuesto');
    const vT = selT.value, vR = selR.value;
    selT.innerHTML = trabajos.map(t => `<option value="${t.id}">${htmlSeguro(etiquetaTrabajoCatalogo(t))}</option>`).join('');
    selR.innerHTML = repuestos.map(r => `<option value="${r.id}">${htmlSeguro(etiquetaRepuestoInventario(r))}</option>`).join('');
    selT.value = vT; selR.value = vR;
  }
  function elegir(tipo, id) {
    if (tipo === 'trabajo') {
      $('item-trabajo').value = id;
      const t = trabajoElegido();
      $('trabajo-buscar').value = t ? etiquetaTrabajoCatalogo(t) : '';
      onTrabajoChange();
    } else {
      $('item-repuesto').value = id;
      const r = repuestoElegido();
      $('repuesto-buscar').value = r ? etiquetaRepuestoInventario(r) : '';
      onRepuestoChange();
    }
  }

  function onTipoChange() {
    const tipo = $('item-tipo').value;
    const libre = tipo === 'otro' || tipo === 'insumo_taller' || tipo === 'insumo_vehiculo';
    $('grupo-trabajo').style.display = tipo === 'mano_obra' ? 'block' : 'none';
    $('grupo-repuesto').style.display = tipo === 'repuesto' ? 'block' : 'none';
    $('grupo-pct').style.display = tipo === 'repuesto' ? 'block' : 'none';
    $('grupo-descripcion').style.display = libre ? 'block' : 'none';
    $('grupo-tipo-otro').style.display = tipo === 'otro' ? 'block' : 'none';
    // Un trabajo del catálogo calcula su precio solo: la cantidad es el N° de veces
    $('grupo-precio').style.display = tipo === 'mano_obra' ? 'none' : 'block';
    $('item-cantidad-label').textContent = tipo === 'mano_obra' ? 'Veces' : 'Cantidad';
    $('item-cantidad').value = '1';
    if (tipo === 'repuesto') onRepuestoChange();
    else if (libre) $('item-precio').value = '';
    error('');
    actualizarCamposTrabajo();
  }
  function onTrabajoChange() {
    const t = trabajoElegido();
    if (!t) return;
    $('item-cantidad').value = '1';
    if (t.precio_fijo != null) $('item-precio').value = Number(t.precio_fijo);
    else { $('item-precio').value = vh(); $('item-horas').value = Number(t.horas_estimadas || 0); }
    actualizarCamposTrabajo();
  }
  // «Horas por trabajo» solo aplica a trabajos que se cobran por hora (sin precio fijo ni opciones)
  function actualizarCamposTrabajo() {
    const t = $('item-tipo').value === 'mano_obra' ? trabajoElegido() : null;
    $('grupo-horas-trabajo').style.display = (t && t.precio_fijo == null && !opcionesDeTrabajo(t).length) ? 'block' : 'none';
    actualizarVista();
  }
  function actualizarVista() {
    const vista = $('item-preview');
    const tipo = $('item-tipo').value;
    if (tipo === 'repuesto') {
      const r = repuestoElegido();
      const pct = Number($('item-pct').value) || 100;
      const cant = Math.round((Number($('item-cantidad').value) || 0) * pct) / 100;
      vista.textContent = r ? `Total: ${fmtNumItem(cant)} × ${fmtMoneda(Number($('item-precio').value) || 0)} = ${fmtMoneda(cant * (Number($('item-precio').value) || 0))}${conStock ? ` · quedan ${fmtNumItem(Math.max(0, Number(r.stock_actual || 0) - cant))} en stock` : ''}` : '';
      return;
    }
    const t = tipo === 'mano_obra' ? trabajoElegido() : null;
    if (!t) { vista.textContent = ''; return; }
    const n = Math.max(1, Number($('item-cantidad').value) || 1);
    if (opcionesDeTrabajo(t).length) {
      vista.textContent = `Este servicio no se realiza solo: al agregarlo se elige una opción (desde ${fmtMoneda(precioNetoTrabajo(t, vh()))} + IVA).`;
    } else if (t.precio_fijo != null) {
      vista.textContent = `Total: ${n} × ${fmtMoneda(t.precio_fijo)} = ${fmtMoneda(Number(t.precio_fijo) * n)}`;
    } else {
      const horas = Math.max(0, Number($('item-horas').value) || 0);
      vista.textContent = `Total: ${n} × ${fmtNumItem(horas)} h = ${fmtNumItem(horas * n)} h · ${fmtMoneda(horas * n * vh())}`;
    }
  }
  function onRepuestoChange() {
    const r = repuestoElegido();
    $('item-pct').value = '100';
    $('item-pct-label').textContent = '100%';
    if (r) $('item-precio').value = r.precio_venta != null ? Number(r.precio_venta) : '';
    actualizarVista();
  }

  async function agregar() {
    error('');
    const tipo = $('item-tipo').value;
    let lineas, info = {};
    if (tipo === 'mano_obra') {
      const t = trabajoElegido();
      if (!t) { error('Busca y elige un trabajo del catálogo (o créalo con «+ Nuevo»).'); return; }
      const n = Math.max(1, Number($('item-cantidad').value) || 1);
      // Servicio con opciones obligatorias (combos): se elige con cuál; la línea sale con su precio cerrado
      let opcion = null;
      if (opcionesDeTrabajo(t).length) {
        opcion = await elegirOpcionTrabajo(t);
        if (!opcion) return;
      }
      const horasPorTrabajo = (opcion || t.precio_fijo != null) ? null : Math.max(0, Number($('item-horas').value) || 0);
      const nombre = (opcion ? `${t.nombre} — ${opcion.nombre}` : t.nombre) + (n > 1 ? ` (x${n})` : '');
      // cantidad × precio_unitario = total; horas / por_hora detallan la mano de obra para el cliente
      lineas = [{ tipo: 'mano_obra', trabajo_id: t.id, repuesto_id: null, tipo_otro: null, descripcion: nombre, ...datosManoObra(t, n, vh(), { opcion, horasPorTrabajo }) }];
      (t.insumos || []).forEach(ins => {
        const m = buscarEnInventario(repuestos, ins.descripcion);
        lineas.push({ tipo: ins.categoria || 'otro', trabajo_id: null, repuesto_id: m.repuesto_id, tipo_otro: null, descripcion: ins.descripcion, cantidad: n, precio_unitario: m.precio });
      });
      info = { trabajo: t };
    } else if (tipo === 'repuesto') {
      const r = repuestoElegido();
      if (!r) { error('Busca y elige un repuesto del inventario (o créalo con «+ Nuevo»).'); return; }
      const pct = Number($('item-pct').value) || 100;
      const cantidad = Math.round((Number($('item-cantidad').value) || 0) * pct) / 100;
      if (!(cantidad > 0)) { error('Indica la cantidad.'); return; }
      if (conStock && Number(r.stock_actual || 0) < cantidad) {
        error(`Stock insuficiente de «${r.nombre}» (disponible: ${fmtNumItem(r.stock_actual || 0)}).`);
        return;
      }
      lineas = [{ tipo: 'repuesto', trabajo_id: null, repuesto_id: r.id, tipo_otro: null, descripcion: r.nombre + (pct < 100 ? ` (${pct}% usado)` : ''), cantidad, precio_unitario: Number($('item-precio').value) || 0 }];
      info = { repuesto: r, cantidad };
    } else {
      const descripcion = $('item-descripcion').value.trim();
      if (!descripcion) { error('Escribe la descripción del ítem.'); $('item-descripcion').focus(); return; }
      lineas = [{
        tipo, trabajo_id: null, repuesto_id: null, descripcion,
        tipo_otro: tipo === 'otro' ? ($('item-tipo-otro').value || 'otro') : null,
        cantidad: Number($('item-cantidad').value) || 0,
        precio_unitario: Number($('item-precio').value) || 0,
      }];
    }
    const boton = $('agregar-item-btn');
    boton.disabled = true;
    let ok;
    try { ok = await onAgregar(lineas, info); } finally { boton.disabled = false; }
    if (ok === false) return;
    $('item-descripcion').value = '';
    $('item-tipo-otro').value = '';
    $('item-preview').textContent = '';
  }

  // «+ Nuevo»: el trabajo o repuesto queda en el catálogo/inventario y elegido aquí mismo
  $('nuevo-trabajo-btn').addEventListener('click', () => {
    ventanaFormulario('Nuevo trabajo del catálogo', `
      <div class="form-group"><label>Nombre del trabajo *</label><input type="text" class="vf-nombre" /></div>
      <div class="form-row">
        <div class="form-group"><label>Horas de taller</label><input type="number" class="vf-horas" step="any" value="1" data-horas /></div>
        <div class="form-group"><label>Precio fijo sin IVA (opcional)</label><input type="number" class="vf-precio" data-formato="precio" placeholder="Vacío = horas × valor hora" /></div>
      </div>
      <p style="color:var(--color-text-muted); font-size:0.8rem; margin:0;">Se agrega al catálogo y queda disponible al instante en todas las pantallas.</p>`,
      async (v) => {
        const nombre = v.valor('.vf-nombre');
        if (!nombre) { v.error('Ingresa el nombre del trabajo.'); return; }
        const { data, error: e } = await supabaseClient.from('trabajos')
          .insert({ nombre, horas_estimadas: Number(v.valor('.vf-horas')) || 1, precio_fijo: v.valor('.vf-precio'), insumos: [] })
          .select('*').single();
        if (e) { v.error('Error: ' + e.message); return; }
        trabajos.push(data);
        trabajos.sort((a, b) => String(a.nombre || '').localeCompare(String(b.nombre || ''), 'es'));
        poblar();
        $('item-tipo').value = 'mano_obra';
        onTipoChange();
        elegir('trabajo', data.id);
        v.cerrar();
      });
  });
  $('nuevo-repuesto-btn').addEventListener('click', () => {
    ventanaFormulario('Nuevo repuesto / insumo', `
      <div class="form-row">
        <div class="form-group"><label>Nombre *</label><input type="text" class="vf-nombre" /></div>
        <div class="form-group"><label>Marca</label><input type="text" class="vf-marca" /></div>
      </div>
      <div class="form-row">
        <div class="form-group"><label>SKU / código</label><input type="text" class="vf-sku" /></div>
        <div class="form-group"><label>Precio venta sin IVA</label><input type="number" class="vf-venta" data-formato="precio" /></div>
        <div class="form-group"><label>Stock inicial</label><input type="number" class="vf-stock" step="any" value="0" /></div>
      </div>`,
      async (v) => {
        const nombre = v.valor('.vf-nombre');
        if (!nombre) { v.error('Ingresa el nombre.'); return; }
        const { data, error: e } = await supabaseClient.from('repuestos')
          .insert({ nombre, marca: v.valor('.vf-marca'), sku: v.valor('.vf-sku'), precio_venta: v.valor('.vf-venta'), stock_actual: Number(v.valor('.vf-stock')) || 0 })
          .select('*').single();
        if (e) { v.error('Error: ' + e.message); return; }
        repuestos.push(data);
        repuestos.sort((a, b) => String(a.nombre || '').localeCompare(String(b.nombre || ''), 'es'));
        poblar();
        $('item-tipo').value = 'repuesto';
        onTipoChange();
        elegir('repuesto', data.id);
        v.cerrar();
      });
  });

  $('item-tipo').addEventListener('change', onTipoChange);
  $('item-trabajo').addEventListener('change', onTrabajoChange);
  $('item-repuesto').addEventListener('change', onRepuestoChange);
  $('item-cantidad').addEventListener('input', actualizarVista);
  $('item-horas').addEventListener('input', actualizarVista);
  $('item-precio').addEventListener('input', actualizarVista);
  $('item-pct').addEventListener('input', () => { $('item-pct-label').textContent = $('item-pct').value + '%'; actualizarVista(); });
  $('agregar-item-btn').addEventListener('click', agregar);
  $('item-descripcion').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); agregar(); } });

  poblar();
  setupCombobox('trabajo-buscar', 'item-trabajo', 'trabajo-lista', trabajos, etiquetaTrabajoCatalogo);
  setupCombobox('repuesto-buscar', 'item-repuesto', 'repuesto-lista', repuestos, etiquetaRepuestoInventario);
  enlazarCamposHoras(contenedor);
  onTipoChange();
  return { recargar: poblar };
}

// ---------- Cliente y vehículo (igual que en la agenda) ----------
// Se reconoce al cliente por RUT o se busca por nombre; si no existe se completa ahí mismo y se crea al guardar.
// El vehículo se elige de su ficha o se ingresa la patente (con los datos del registro público si hay clave).
//   contenedor · clientes / vehiculos: arreglos de la pantalla (se les agregan los nuevos)
//   alCambiar({ clienteId, vehiculoId, vehiculo }): avisa cada cambio (p. ej. para traer el kilometraje)
//   titulo: encabezado del cuadro ('' = sin encabezado, si la pantalla ya tiene el suyo)
// Devuelve { fijar(clienteId, vehiculoId), limpiar(), valores(), preparar() }.
//   preparar(): crea lo nuevo y devuelve { clienteId, vehiculoId } o { error }.
function crearSelectorCliente({ contenedor, clientes, vehiculos, alCambiar, titulo = '👤 Cliente y vehículo' }) {
  const uid = 'sc' + Math.random().toString(36).slice(2, 7);
  contenedor.innerHTML = `
    <div class="reconocer-cliente selector-cliente">
      ${titulo ? `<h3>${titulo}</h3>` : ''}
      <div class="form-row">
        <div class="form-group">
          <label for="${uid}-rut">RUT del cliente</label>
          <input type="text" id="${uid}-rut" data-formato="rut" placeholder="12.345.678-9" autocomplete="off" maxlength="12" />
          <p class="reconocer-estado sc-rut-estado"></p>
        </div>
        <div class="form-group">
          <label for="${uid}-buscar">o búscalo por nombre</label>
          <div class="combobox-wrap">
            <div class="select-con-boton">
              <input type="text" id="${uid}-buscar" placeholder="Escribe para buscar..." autocomplete="off" />
              <button type="button" class="btn-secondary btn-mini sc-nuevo-btn" title="Cliente nuevo">+ Nuevo</button>
            </div>
            <div class="combobox-lista" id="${uid}-lista" style="display:none;"></div>
          </div>
          <select id="${uid}-sel" style="display:none;"></select>
        </div>
      </div>
      <div class="sc-ficha" style="display:none;"></div>
      <div class="sc-nuevo" style="display:none;">
        <div class="form-row">
          <div class="form-group"><label>Nombre *</label><input type="text" class="sc-nombre" autocomplete="off" /></div>
          <div class="form-group"><label>Teléfono</label><input type="tel" class="sc-tel" data-formato="telefono" placeholder="+56 9 1234 5678" autocomplete="off" /></div>
          <div class="form-group"><label>Correo</label><input type="email" class="sc-email" placeholder="cliente@correo.cl" autocomplete="off" /></div>
        </div>
      </div>
      <div class="sc-vehiculo vehiculo-nuevo-bloque" style="display:none;">
        <div class="form-row">
          <div class="form-group"><label>Patente</label><input type="text" class="sc-pat" maxlength="7" placeholder="ABCD12" autocomplete="off" style="text-transform:uppercase;" /></div>
          <div class="form-group"><label>Marca</label><input type="text" class="sc-marca" /></div>
          <div class="form-group"><label>Modelo</label><input type="text" class="sc-modelo" /></div>
          <div class="form-group"><label>Año</label><input type="number" class="sc-anio" min="1950" max="2100" /></div>
        </div>
        <div class="form-row">
          <div class="form-group"><label>Kilometraje</label><input type="number" class="sc-km" min="0" placeholder="km" /></div>
          <div class="form-group"><label>Cilindrada / motor</label><input type="text" class="sc-motor" placeholder="ej. 1.6" /></div>
          <div class="form-group"><label>Combustible</label>
            <select class="sc-comb"><option value="">–</option><option>Gasolina</option><option>Diésel</option><option>Híbrido</option><option>Eléctrico</option><option>Gas</option></select></div>
        </div>
        <p class="reconocer-estado sc-pat-estado" style="margin:-0.4rem 0 0.5rem;"></p>
      </div>
    </div>`;

  const q = (sel) => contenedor.querySelector(sel);
  const rutEl = document.getElementById(uid + '-rut');
  const estado = (sel, texto, clase, html) => {
    const el = q(sel);
    el.className = 'reconocer-estado ' + sel.slice(1) + (clase ? ' ' + clase : '');
    if (html) el.innerHTML = texto; else el.textContent = texto;
  };
  const MSG_RUT = 'Escribe el RUT: si ya es cliente, se reconoce solo.';
  let clienteId = null, vehiculoId = null, modoNuevo = false, vehiculoNuevo = false;
  let datosPatente = null, seqPatente = 0, timerRut = null, timerPat = null;

  const cliente = () => clientes.find(c => c.id === clienteId) || null;
  const avisar = () => { if (alCambiar) alCambiar({ clienteId, vehiculoId, vehiculo: vehiculos.find(v => v.id === vehiculoId) || null }); };

  function poblarLista() {
    const sel = document.getElementById(uid + '-sel');
    sel.innerHTML = '<option value=""></option>' + clientes.map(c => `<option value="${c.id}">${htmlSeguro(c.nombre)}</option>`).join('');
    sel.value = clienteId || '';
  }

  function renderFicha() {
    const cont = q('.sc-ficha');
    const c = cliente();
    if (!c) { cont.style.display = 'none'; cont.innerHTML = ''; return; }
    const vehs = vehiculos.filter(v => v.cliente_id === c.id);
    const encabezado = vehs.length === 0 ? 'No tiene vehículos registrados: ingresa la patente.'
      : vehs.length === 1 ? 'Vehículo del cliente:' : `Tiene ${vehs.length} vehículos: elige el que corresponde.`;
    cont.innerHTML = `
      <div class="cliente-ficha">
        <div class="ficha-nombre">✅ ${htmlSeguro(c.nombre)} <button type="button" class="btn-secondary btn-mini sc-cambiar" style="margin-left:0.4rem;">Cambiar</button></div>
        <div class="ficha-datos">
          <span>RUT: ${c.rut ? htmlSeguro(formatearRut(c.rut)) : 'no registrado'}</span>
          ${c.telefono ? `<span>📞 ${htmlSeguro(c.telefono)}</span>` : ''}
          ${c.email ? `<span>✉️ ${htmlSeguro(c.email)}</span>` : ''}
        </div>
        <div class="ficha-vehiculos">
          <div style="font-size:0.8rem; color:var(--color-text-muted); margin-bottom:0.25rem;">${encabezado}</div>
          ${vehs.map(v => `
            <label class="ficha-vehiculo${v.id === vehiculoId && !vehiculoNuevo ? ' elegido' : ''}">
              <input type="radio" name="${uid}-veh" value="${v.id}" ${v.id === vehiculoId && !vehiculoNuevo ? 'checked' : ''} />
              <span class="veh-patente">${htmlSeguro(v.patente)}</span>
              <span class="veh-detalle">${htmlSeguro([v.marca, v.modelo, v.anio].filter(Boolean).join(' '))}${v.kilometraje ? ` · ${Number(v.kilometraje).toLocaleString('es-CL')} km` : ''}</span>
            </label>`).join('')}
          <label class="ficha-vehiculo${vehiculoNuevo ? ' elegido' : ''}">
            <input type="radio" name="${uid}-veh" value="__nuevo__" ${vehiculoNuevo ? 'checked' : ''} />
            <span class="veh-detalle">➕ Otro vehículo (ingresar patente)</span>
          </label>
          <label class="ficha-vehiculo${!vehiculoId && !vehiculoNuevo ? ' elegido' : ''}">
            <input type="radio" name="${uid}-veh" value="" ${!vehiculoId && !vehiculoNuevo ? 'checked' : ''} />
            <span class="veh-detalle">Sin vehículo</span>
          </label>
        </div>
      </div>`;
    cont.style.display = 'block';
  }

  function mostrarVehiculoNuevo(mostrar) {
    vehiculoNuevo = !!mostrar;
    q('.sc-vehiculo').style.display = mostrar ? 'block' : 'none';
    if (!mostrar) {
      ['.sc-pat', '.sc-marca', '.sc-modelo', '.sc-anio', '.sc-km', '.sc-motor', '.sc-comb'].forEach(s => { q(s).value = ''; });
      estado('.sc-pat-estado', '');
      datosPatente = null; seqPatente++;
    }
  }
  function mostrarClienteNuevo(mostrar) {
    modoNuevo = !!mostrar;
    q('.sc-nuevo').style.display = mostrar ? 'block' : 'none';
    if (mostrar) { mostrarVehiculoNuevo(true); q('.sc-nombre').focus(); }
    else ['.sc-nombre', '.sc-tel', '.sc-email'].forEach(s => { q(s).value = ''; });
  }

  // Elige un cliente existente: si tiene un solo vehículo queda elegido; si no tiene, se pide la patente
  function seleccionar(id, vehId) {
    clienteId = id || null;
    const c = cliente();
    mostrarClienteNuevo(false);
    mostrarVehiculoNuevo(false);
    poblarLista();
    document.getElementById(uid + '-buscar').value = c ? c.nombre : '';
    rutEl.value = c && c.rut ? formatearRut(c.rut) : '';
    estado('.sc-rut-estado', c ? (c.rut ? '✅ Cliente reconocido.' : 'Cliente sin RUT registrado.') : MSG_RUT, c ? (c.rut ? 'ok' : 'aviso') : '');
    const vehs = c ? vehiculos.filter(v => v.cliente_id === c.id) : [];
    vehiculoId = vehId !== undefined ? (vehId || null) : (vehs.length === 1 ? vehs[0].id : null);
    if (c && !vehs.length && vehId === undefined) mostrarVehiculoNuevo(true);
    renderFicha();
    avisar();
  }

  function buscarPorRut() {
    const limpio = rutLimpio(rutEl.value);
    const actual = cliente();
    if (actual && actual.rut && rutLimpio(actual.rut) === limpio) return;
    if (clienteId || modoNuevo) { clienteId = null; vehiculoId = null; mostrarClienteNuevo(false); mostrarVehiculoNuevo(false); renderFicha(); poblarLista(); document.getElementById(uid + '-buscar').value = ''; avisar(); }
    if (!limpio) { estado('.sc-rut-estado', MSG_RUT); return; }
    if (limpio.length < 7) { estado('.sc-rut-estado', 'Sigue escribiendo el RUT…'); return; }
    const encontrado = clientes.find(c => c.rut && rutLimpio(c.rut) === limpio);
    if (encontrado) { seleccionar(encontrado.id); return; }
    if (!rutValido(limpio)) {
      estado('.sc-rut-estado', limpio.length >= 8 ? '⚠ El RUT no es válido: revisa el dígito verificador.' : 'Sigue escribiendo el RUT…', limpio.length >= 8 ? 'aviso' : '');
      return;
    }
    mostrarClienteNuevo(true);
    estado('.sc-rut-estado', 'ℹ️ Cliente nuevo: completa sus datos. Se guarda en Clientes al guardar.', 'aviso');
  }

  async function resolverPatente() {
    const p = normalizarPatente(q('.sc-pat').value);
    const seq = ++seqPatente;
    datosPatente = null;
    if (!p) { estado('.sc-pat-estado', ''); return; }
    if (!patenteValida(p)) { estado('.sc-pat-estado', p.length >= 6 ? '⚠ La patente no tiene un formato válido (ej. ABCD12 o AB1234).' : '', 'aviso'); return; }
    const existente = vehiculos.find(v => v.patente === p);
    if (existente) {
      if (existente.cliente_id === clienteId) { seleccionar(clienteId, existente.id); return; }
      const dueno = clientes.find(c => c.id === existente.cliente_id);
      estado('.sc-pat-estado', `⚠ Esa patente ya está registrada${dueno ? ` a nombre de <strong>${htmlSeguro(dueno.nombre)}</strong>` : ''}. <button type="button" class="btn-secondary btn-mini sc-usar-dueno" data-cliente="${htmlSeguro(existente.cliente_id)}" data-vehiculo="${htmlSeguro(existente.id)}">Usar ese cliente y vehículo</button>`, 'aviso', true);
      return;
    }
    estado('.sc-pat-estado', 'Buscando los datos del vehículo…');
    const r = await consultarPatente(p);
    if (seq !== seqPatente) return;
    if (r.estado === 'ok') {
      const d = r.datos;
      q('.sc-marca').value = d.marca || '';
      q('.sc-modelo').value = d.modelo || '';
      q('.sc-anio').value = d.anio || '';
      if (d.kilometraje) q('.sc-km').value = d.kilometraje;
      if (d.cilindrada) q('.sc-motor').value = d.cilindrada;
      const comb = normalizarCombustible(d.combustible);
      if (comb) {
        const s = q('.sc-comb');
        if (![...s.options].some(o => o.value === comb || o.text === comb)) s.add(new Option(comb, comb));
        s.value = comb;
      }
      datosPatente = { patente: p, ...d };
      estado('.sc-pat-estado', `✅ Datos del registro público: ${[d.marca, d.modelo, d.anio].filter(Boolean).join(' ')}. Revísalos antes de guardar.`, 'ok');
    } else if (r.estado === 'sin_clave' || r.estado === 'no_encontrado') {
      estado('.sc-pat-estado', 'Vehículo nuevo: completa marca, modelo y año. Se guarda al guardar.', 'aviso');
    } else if (r.estado === 'limite') {
      estado('.sc-pat-estado', 'Se alcanzó el límite de consultas de patentes de hoy: completa los datos a mano.', 'aviso');
    } else {
      estado('.sc-pat-estado', `No se pudo consultar la patente${r.mensaje ? ` (${r.mensaje})` : ''}. Completa los datos a mano.`, 'aviso');
    }
  }

  // Crea el cliente y/o el vehículo nuevos. Devuelve { clienteId, vehiculoId } o { error }.
  async function preparar() {
    let id = clienteId;
    if (!id) {
      if (!modoNuevo) return { error: 'Elige el cliente (por RUT o por nombre) o crea uno nuevo.' };
      const nombre = q('.sc-nombre').value.trim();
      const rut = rutEl.value.trim() ? formatearRut(rutEl.value) : '';
      const telefono = q('.sc-tel').value.trim() ? formatearTelefonoCL(q('.sc-tel').value) : '';
      const email = q('.sc-email').value.trim().toLowerCase();
      if (!nombre) return { error: 'Ingresa el nombre del cliente nuevo.' };
      if (rut && !rutValido(rut)) return { error: 'El RUT del cliente no es válido: revisa el dígito verificador.' };
      if (telefono && !telefonoValidoCL(telefono)) return { error: 'El teléfono no es válido (9 dígitos, ej. +56 9 1234 5678).' };
      if (email && !correoValido(email)) return { error: 'El correo del cliente no es válido.' };
      // Sin RUT: si ya existe alguien con ese teléfono, se evita duplicarlo
      const tel = telefono ? telefonoNacional(telefono) : '';
      const mismo = !rut && tel && clientes.find(c => c.telefono && telefonoNacional(c.telefono) === tel);
      if (mismo && confirm(`Ya existe «${mismo.nombre}» con ese teléfono.\n\n¿Es la misma persona?\n\nAceptar: usar ese cliente.\nCancelar: crear un cliente nuevo.`)) {
        id = mismo.id;
      } else {
        const { data, error } = await supabaseClient.from('clientes')
          .insert({ nombre, rut: rut || null, telefono: telefono || null, email: email || null })
          .select('id, nombre, rut, telefono, email').single();
        if (error) {
          return { error: /duplicate|unique|23505/i.test(`${error.code || ''} ${error.message || ''}`)
            ? `Ya existe un cliente con el RUT ${rut} (puede estar desactivado: revísalo en Clientes).`
            : `No se pudo guardar el cliente: ${error.message}` };
        }
        clientes.push(data);
        id = data.id;
      }
      clienteId = id;
      modoNuevo = false;
      q('.sc-nuevo').style.display = 'none';
    }
    let vehId = vehiculoId;
    const patente = normalizarPatente(q('.sc-pat').value);
    if (vehiculoNuevo && patente) {
      if (!patenteValida(patente)) return { error: 'La patente no tiene un formato válido (ej. ABCD12 o AB1234).' };
      const dupe = vehiculos.find(v => v.patente === patente);
      if (dupe) {
        if (dupe.cliente_id !== id) {
          const dueno = clientes.find(c => c.id === dupe.cliente_id);
          return { error: `La patente ${patente} ya está registrada${dueno ? ` a nombre de ${dueno.nombre}` : ''}. Usa «Usar ese cliente y vehículo».` };
        }
        vehId = dupe.id;
      } else {
        const ficha = (datosPatente && datosPatente.patente === patente) ? fichaDesdeRegistro(datosPatente) : { columnas: {}, notas: '' };
        const columnas = { ...ficha.columnas };
        const km = Math.round(Number(q('.sc-km').value));
        if (km > 0) columnas.kilometraje = km;
        if (q('.sc-motor').value.trim()) columnas.motor = q('.sc-motor').value.trim();
        if (q('.sc-comb').value) columnas.combustible = q('.sc-comb').value;
        const basico = { cliente_id: id, patente, marca: q('.sc-marca').value.trim() || null, modelo: q('.sc-modelo').value.trim() || null, anio: q('.sc-anio').value || null };
        let { data, error } = await supabaseClient.from('vehiculos').insert({ ...basico, ...columnas, notas: ficha.notas || null }).select('*').single();
        if (faltaColumnaNueva(error)) {
          const { propias, texto } = columnasConocidasHoy(columnas);
          ({ data, error } = await supabaseClient.from('vehiculos')
            .insert({ ...basico, ...propias, notas: [texto, ficha.notas].filter(Boolean).join(' · ') || null }).select('*').single());
        }
        if (error) {
          return { error: /duplicate|unique|23505/i.test(`${error.code || ''} ${error.message || ''}`)
            ? `La patente ${patente} ya existe en el sistema (puede estar desactivada: revísala en Vehículos).`
            : `No se pudo guardar el vehículo: ${error.message}` };
        }
        vehiculos.push(data);
        vehId = data.id;
      }
    } else if (vehiculoNuevo) {
      vehId = null;
    }
    // Queda mostrado como cliente/vehículo existentes (por si se sigue editando)
    seleccionar(id, vehId);
    return { clienteId: id, vehiculoId: vehId };
  }

  // Eventos
  enlazarFormato(rutEl, formatearRut, () => { clearTimeout(timerRut); timerRut = setTimeout(buscarPorRut, 400); });
  enlazarFormato(q('.sc-pat'), normalizarPatente, () => {
    clearTimeout(timerPat);
    timerPat = setTimeout(resolverPatente, normalizarPatente(q('.sc-pat').value).length >= 6 ? 350 : 1800);
  });
  document.getElementById(uid + '-sel').addEventListener('change', (e) => { if (e.target.value) seleccionar(e.target.value); });
  q('.sc-nuevo-btn').addEventListener('click', () => {
    clienteId = null; vehiculoId = null;
    renderFicha(); poblarLista();
    document.getElementById(uid + '-buscar').value = '';
    mostrarClienteNuevo(true);
    estado('.sc-rut-estado', rutEl.value.trim() ? 'ℹ️ Cliente nuevo: completa sus datos.' : 'Cliente nuevo: el RUT es opcional, pero ayuda a reconocerlo la próxima vez.', 'aviso');
    avisar();
  });
  contenedor.addEventListener('change', (e) => {
    if (!e.target.matches(`input[name="${uid}-veh"]`)) return;
    if (e.target.value === '__nuevo__') { vehiculoId = null; mostrarVehiculoNuevo(true); q('.sc-pat').focus(); }
    else { mostrarVehiculoNuevo(false); vehiculoId = e.target.value || null; }
    renderFicha();
    avisar();
  });
  contenedor.addEventListener('click', (e) => {
    if (e.target.closest('.sc-cambiar')) {
      clienteId = null; vehiculoId = null;
      mostrarVehiculoNuevo(false);
      renderFicha(); poblarLista();
      rutEl.value = '';
      document.getElementById(uid + '-buscar').value = '';
      estado('.sc-rut-estado', MSG_RUT);
      rutEl.focus();
      avisar();
      return;
    }
    const usar = e.target.closest('.sc-usar-dueno');
    if (usar) seleccionar(usar.dataset.cliente, usar.dataset.vehiculo);
  });

  poblarLista();
  setupCombobox(uid + '-buscar', uid + '-sel', uid + '-lista', clientes, c => c.nombre + (c.rut ? ` · ${formatearRut(c.rut)}` : ''));
  estado('.sc-rut-estado', MSG_RUT);

  return {
    fijar: (cId, vId) => { rutEl.value = ''; seleccionar(cId || null, vId || null); if (!cId) estado('.sc-rut-estado', MSG_RUT); },
    limpiar: () => {
      clienteId = null; vehiculoId = null;
      mostrarClienteNuevo(false); mostrarVehiculoNuevo(false);
      rutEl.value = '';
      document.getElementById(uid + '-buscar').value = '';
      renderFicha(); poblarLista();
      estado('.sc-rut-estado', MSG_RUT);
    },
    valores: () => ({ clienteId, vehiculoId }),
    preparar,
    recargar: poblarLista,
  };
}
