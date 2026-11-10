/* =========================================================================
   APERTURA "LAS ALAS" · Angels · jugador y staff, una vez por sesion.
   Un remolino de luz se junta en las dos alas: primero el trazo holografico,
   luego las plumas solidas que se abren. El halo cae girando con un parpadeo
   digital, se asienta sobre las alas y suelta una onda de energia; las alas
   dan un aletazo, la escena se aplana y el logo aterriza en la cabecera (o en
   el logo del rail o del login en el staff). En Hoy el halo se separa y se
   convierte en el aro de Hoy. Tocar salta. Sin WebGL, con movimiento
   reducido o si three.js no carga, no pasa nada: la app abre directo.
   Unidades: pixeles del logo angels-mark.png (776 x 248), centro en (0,0).
   ========================================================================= */
try {
  var raiz = document.documentElement;
  if(!raiz.classList.contains('apertura-3d')) throw new Error('sin apertura');
  var overlay = document.getElementById('v2-apertura');
  var canvas = document.getElementById('v2-gl');
  var pista = document.getElementById('v2-pista');
  if(!overlay || !canvas) throw new Error('sin lienzo');
  clearTimeout(window.V2_APERTURA_TIMER);

  /* Fondo de la apertura: azul noche con rejilla tenue. Se desvanece en el
     traspaso para dejar ver la app. */
  var fondo = document.createElement('div');
  fondo.id = 'ang-fondo';
  var estiloFondo = document.createElement('style');
  estiloFondo.textContent = '#ang-fondo{position:absolute;inset:0;opacity:1;transition:opacity .45s ease;' +
    'background:radial-gradient(ellipse at 50% 44%,rgba(81,183,228,0.16) 0%,rgba(81,183,228,0) 42%),' +
    'linear-gradient(rgba(81,183,228,0.06) 1px,transparent 1px) 0 0/30px 30px,' +
    'linear-gradient(90deg,rgba(81,183,228,0.06) 1px,transparent 1px) 0 0/30px 30px,' +
    'radial-gradient(ellipse at 50% 44%,#22337a 0%,#121b4a 48%,#060a1d 100%);}' +
    '#ang-fondo.fuera{opacity:0;}' +
    '#v2-apertura #v2-pista.ang-claro{color:rgba(255,255,255,0.72);}';
  document.head.appendChild(estiloFondo);
  overlay.insertBefore(fondo, canvas);
  if(pista) pista.classList.add('ang-claro');

  var renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.setClearColor(0x000000, 0);

  var scene = new THREE.Scene();
  var camera = new THREE.PerspectiveCamera(26, 1, 10, 20000);
  var PROF = 14;
  scene.add(new THREE.AmbientLight(0xffffff, 1.25));
  var clave = new THREE.DirectionalLight(0xffffff, 1.0); clave.position.set(-300, 600, 1400); scene.add(clave);
  var barrido = new THREE.DirectionalLight(0xffffff, 1.8); barrido.position.set(-1600, 300, 900); scene.add(barrido);
  var contra = new THREE.DirectionalLight(0xbfe9ff, 0.5); contra.position.set(500, -400, 900); scene.add(contra);

  var CIELO = 0x51b7e4, ROSA = 0xeb448f, HIELO = 0xc8f1ff;

  var g = new THREE.Group(); scene.add(g);

  /* ---------- Alas ----------
     Cada pluma sale de la raiz del ala (abajo, hacia el centro) y se abre
     en abanico hacia su punta. Forma de guadana: dos curvas que se doblan
     hacia el mismo lado. El ala derecha es el espejo de la izquierda. */
  var RAIZ = new THREE.Vector2(-88, -88);
  var PLUMAS = [
    { punta: new THREE.Vector2(-374, 116), curva: 92, grosor: 0.62 },
    { punta: new THREE.Vector2(-370, 60),  curva: 66, grosor: 0.58 },
    { punta: new THREE.Vector2(-356, 4),   curva: 52, grosor: 0.56 },
    { punta: new THREE.Vector2(-318, -42), curva: 40, grosor: 0.54 },
    { punta: new THREE.Vector2(-246, -74), curva: 28, grosor: 0.52 }
  ];
  function bez(a, c, b, t){ var u = 1 - t; return new THREE.Vector2(u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y); }
  function geoPluma(p){
    var d = new THREE.Vector2(p.punta.x - RAIZ.x, p.punta.y - RAIZ.y);
    var n = new THREE.Vector2(-d.y, d.x).normalize();
    var o = new THREE.Vector2(0, 0), tip = d.clone();
    var cFuera = new THREE.Vector2(d.x * 0.5 + n.x * p.curva, d.y * 0.5 + n.y * p.curva);
    var cDentro = new THREE.Vector2(d.x * 0.56 + n.x * p.curva * (1 - p.grosor), d.y * 0.56 + n.y * p.curva * (1 - p.grosor));
    var sh = new THREE.Shape();
    sh.moveTo(o.x, o.y);
    sh.quadraticCurveTo(cFuera.x, cFuera.y, tip.x, tip.y);
    sh.quadraticCurveTo(cDentro.x, cDentro.y, o.x, o.y);
    var geo = new THREE.ExtrudeGeometry(sh, { depth: PROF, bevelEnabled: true, bevelThickness: 2, bevelSize: 1.4, bevelSegments: 2, curveSegments: 28 });
    geo.translate(0, 0, -PROF / 2);
    return { geo: geo, d: d, cFuera: cFuera, cDentro: cDentro };
  }
  var alas = [];      // [{ pivote, plumas:[{pivote, solida, trazo, info}] }]
  var matsSolidos = [], matsTrazo = [];
  function construyeAla(lado){
    var cont = new THREE.Group(); if(lado < 0) cont.scale.x = -1; g.add(cont);
    var pivote = new THREE.Group(); pivote.position.set(RAIZ.x, RAIZ.y, 0); cont.add(pivote);
    var ala = { pivote: pivote, plumas: [] };
    PLUMAS.forEach(function(p, i){
      var info = geoPluma(p);
      var mS = new THREE.MeshStandardMaterial({ color: CIELO, emissive: 0x1b78b0, emissiveIntensity: 0.35, roughness: 0.32, metalness: 0.2, transparent: true, opacity: 0, side: THREE.DoubleSide });
      var mT = new THREE.LineBasicMaterial({ color: HIELO, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
      matsSolidos.push(mS); matsTrazo.push(mT);
      var pp = new THREE.Group(); pivote.add(pp);
      var solida = new THREE.Mesh(info.geo, mS);
      var trazo = new THREE.LineSegments(new THREE.EdgesGeometry(info.geo, 25), mT);
      pp.add(solida); pp.add(trazo);
      ala.plumas.push({ pivote: pp, solida: solida, trazo: trazo, mS: mS, mT: mT, info: info, i: i });
    });
    alas.push(ala);
  }
  construyeAla(1); construyeAla(-1);

  /* ---------- Halo ----------
     Aro inclinado: visto de frente es la elipse rosa del logo (260 x 100). */
  var HALO_R = 130, HALO_Y = 26, HALO_INCL = Math.acos(100 / 260);
  var halo = new THREE.Group(); halo.position.set(0, HALO_Y, 0); g.add(halo);
  var haloIncl = new THREE.Group(); haloIncl.rotation.x = HALO_INCL; halo.add(haloIncl);
  var mHalo = new THREE.MeshStandardMaterial({ color: ROSA, emissive: ROSA, emissiveIntensity: 0.45, roughness: 0.25, metalness: 0.15, transparent: true, opacity: 0 });
  var aro = new THREE.Mesh(new THREE.TorusGeometry(HALO_R - 9, 9, 24, 160), mHalo);
  var mBrillo = new THREE.MeshBasicMaterial({ color: ROSA, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  var brillo = new THREE.Mesh(new THREE.TorusGeometry(HALO_R - 9, 22, 16, 160), mBrillo);
  haloIncl.add(aro); haloIncl.add(brillo);

  /* ---------- Onda de energia y escaner ---------- */
  function anillo(color){
    var m = new THREE.MeshBasicMaterial({ color: color, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
    var r = new THREE.Mesh(new THREE.RingGeometry(0.94, 1, 160), m); r.position.set(0, HALO_Y, 0); r.visible = false; g.add(r); return r;
  }
  var onda1 = anillo(ROSA), onda2 = anillo(CIELO);
  var mScan = new THREE.MeshBasicMaterial({ color: CIELO, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  var scan = new THREE.Mesh(new THREE.PlaneGeometry(900, 5), mScan); scan.position.z = 30; g.add(scan);
  var mScanHalo = new THREE.MeshBasicMaterial({ color: CIELO, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  var scanHalo = new THREE.Mesh(new THREE.PlaneGeometry(900, 60), mScanHalo); scanHalo.position.z = 29; g.add(scanHalo);

  /* ---------- Particulas ----------
     Salen de un remolino amplio, llegan a su punto en una pluma o en el halo
     y se apagan; las chispas se quedan hasta el aletazo y salen disparadas. */
  function texPunto(){
    var c = document.createElement('canvas'); c.width = 64; c.height = 64;
    var x = c.getContext('2d'); var gr = x.createRadialGradient(32, 32, 0, 32, 32, 32);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,0.85)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    x.fillStyle = gr; x.fillRect(0, 0, 64, 64);
    var t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
  }
  var NP = (window.innerWidth || 400) < 520 ? 1300 : 1900;
  var pos = new Float32Array(NP * 3), col = new Float32Array(NP * 3);
  var P = [];
  var cCielo = new THREE.Color(CIELO), cRosa = new THREE.Color(ROSA), cBlanco = new THREE.Color(0xffffff), cHielo = new THREE.Color(HIELO);
  var pesos = PLUMAS.map(function(p){ return p.curva + 30; });
  var sumaPesos = pesos.reduce(function(a, b){ return a + b; }, 0);
  function eligePluma(){ var r = Math.random() * sumaPesos; for(var i = 0; i < pesos.length; i++){ r -= pesos[i]; if(r <= 0) return i; } return pesos.length - 1; }
  for(var k = 0; k < NP; k++){
    var esHalo = Math.random() < 0.16, objetivo, f = -1, base;
    if(esHalo){
      var a = Math.random() * Math.PI * 2;
      objetivo = new THREE.Vector3(Math.cos(a) * (HALO_R - 9), HALO_Y + Math.sin(a) * (HALO_R - 9) * Math.cos(HALO_INCL), Math.sin(a) * 40);
      base = Math.random() < 0.7 ? cRosa : cBlanco;
    } else {
      f = eligePluma();
      var inf = geoPluma(PLUMAS[f]);
      var tt = Math.pow(Math.random(), 0.8), vv = Math.random();
      var pf = bez(new THREE.Vector2(0, 0), inf.cFuera, inf.d, tt), pd = bez(new THREE.Vector2(0, 0), inf.cDentro, inf.d, tt);
      var lado = Math.random() < 0.5 ? 1 : -1;
      var x0 = RAIZ.x + pf.x + (pd.x - pf.x) * vv, y0 = RAIZ.y + pf.y + (pd.y - pf.y) * vv;
      objetivo = new THREE.Vector3(x0 * lado, y0, (Math.random() - 0.5) * 16);
      inf.geo.dispose();
      base = Math.random() < 0.2 ? cBlanco : (Math.random() < 0.5 ? cHielo : cCielo);
    }
    var r0 = 700 + Math.random() * 1100;
    var dirB = new THREE.Vector3(objetivo.x, objetivo.y - HALO_Y, (Math.random() - 0.5) * 300).normalize();
    P.push({
      obj: objetivo, r0: r0, a0: Math.random() * Math.PI * 2, w: (2.6 + Math.random() * 2.2) * (Math.random() < 0.85 ? 1 : -1),
      y0: (Math.random() - 0.5) * 900, z0: (Math.random() - 0.5) * 700,
      tLlega: esHalo ? 1250 + Math.random() * 450 : 650 + (f < 0 ? 0 : f) * 85 + Math.random() * 520,
      chispa: Math.random() < 0.38, dir: dirB, dist: 240 + Math.random() * 620, base: base, brillo: 0.55 + Math.random() * 0.45
    });
  }
  var geoP = new THREE.BufferGeometry();
  geoP.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geoP.setAttribute('color', new THREE.BufferAttribute(col, 3));
  var mP = new THREE.PointsMaterial({ size: 9, map: texPunto(), vertexColors: true, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, sizeAttenuation: true });
  var puntos = new THREE.Points(geoP, mP); puntos.frustumCulled = false; g.add(puntos);

  var vw = 1, vh = 1, s = 0.5, Wlogo = 300, yRest = 0;
  var LOGO_W = 776;
  function encuadre(){
    vw = window.innerWidth; vh = window.innerHeight;
    Wlogo = Math.min(vw * 0.86, 600); s = Wlogo / LOGO_W;
    var fov = camera.fov * Math.PI / 180;
    var d = (vh / s) / (2 * Math.tan(fov / 2));
    camera.aspect = vw / vh; camera.position.set(0, 0, d); camera.lookAt(0, 0, 0); camera.updateProjectionMatrix();
    renderer.setSize(vw, vh, false);
    yRest = (vh * 0.06) / s;
    mP.size = Math.max(5, 3.2 / s);
  }
  function aMundo(px, py){ return new THREE.Vector3((px - vw / 2) / s, (vh / 2 - py) / s, 0); }
  /* Mide el logo de destino por su imagen o su svg, no por la placa. */
  function cajaLogo(el){
    if(!el) return null;
    var dentro = el.querySelector ? el.querySelector('img,svg') : null;
    var r = (dentro || el).getBoundingClientRect();
    if(!r.width) return null;
    var w = r.width;
    if(!dentro){
      try { var cs = getComputedStyle(el); w = Math.max(1, r.width - (parseFloat(cs.paddingLeft) || 0) - (parseFloat(cs.paddingRight) || 0)); } catch(e){}
    }
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: w };
  }
  function centroDe(id){ var el = document.getElementById(id); if(!el) return null; var r = el.getBoundingClientRect(); if(!r.width) return null; return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width }; }
  function destinoStaff(){
    try {
      var ids = ['st-logo-login', 'st-logo-rail'];
      for(var i = 0; i < ids.length; i++){
        var el = document.getElementById(ids[i]);
        if(!el || !el.offsetParent) continue;
        var c = cajaLogo(el); if(c) return c;
      }
    } catch(e){}
    return null;
  }
  function staffLogos(cls){
    try { var els = document.querySelectorAll('.st-logo-dest'); for(var i = 0; i < els.length; i++) els[i].classList.add(cls); } catch(e){}
  }
  window.addEventListener('resize', function(){ try { encuadre(); } catch(e){} });

  function clamp01(x){ return x < 0 ? 0 : x > 1 ? 1 : x; }
  function tr(t, a, b){ return clamp01((t - a) / (b - a)); }
  function outCubic(x){ return 1 - Math.pow(1 - x, 3); }
  function outQuint(x){ return 1 - Math.pow(1 - x, 5); }
  function inOutCubic(x){ return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
  function outBack(x){ var c1 = 1.5, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); }
  function mix(a, b, t){ return a + (b - a) * t; }

  var T_ALETAZO = 1900, T_HAND = 2450, DUR_HAND = 720, ESPERA_MAX = 6500;
  var corriendo = false, t0 = 0, fase = 'intro', tHand = 0, destino = null, contenido = null, terminado = false;

  function frameParticulas(t){
    for(var i = 0; i < NP; i++){
      var p = P[i], x, y, z, b;
      var ent = tr(t, 0, 320);
      if(t < p.tLlega){
        var ang = p.a0 + p.w * (t / 1000);
        var enc = 1 - 0.6 * tr(t, 0, p.tLlega);
        var vx = Math.cos(ang) * p.r0 * enc, vy = p.y0 * enc + Math.sin(ang) * p.r0 * enc * 0.32, vz = p.z0 * enc + Math.sin(ang) * p.r0 * enc * 0.55;
        var kk = outCubic(tr(t, p.tLlega - 650, p.tLlega));
        x = mix(vx, p.obj.x, kk); y = mix(vy, p.obj.y, kk); z = mix(vz, p.obj.z, kk);
        b = ent * (0.55 + 0.45 * kk);
      } else if(p.chispa){
        var eb = outCubic(tr(t, T_ALETAZO, T_ALETAZO + 700));
        x = p.obj.x + p.dir.x * p.dist * eb; y = p.obj.y + p.dir.y * p.dist * eb; z = p.obj.z + p.dir.z * p.dist * eb;
        b = t < T_ALETAZO ? 0.7 + 0.3 * Math.sin(t * 0.02 + i) : 1 - tr(t, T_ALETAZO, T_ALETAZO + 700);
      } else {
        x = p.obj.x; y = p.obj.y; z = p.obj.z;
        b = 1 - tr(t, p.tLlega, p.tLlega + 420);
      }
      var j = i * 3;
      pos[j] = x; pos[j + 1] = y; pos[j + 2] = z;
      b *= p.brillo;
      col[j] = p.base.r * b; col[j + 1] = p.base.g * b; col[j + 2] = p.base.b * b;
    }
    geoP.attributes.position.needsUpdate = true;
    geoP.attributes.color.needsUpdate = true;
  }

  function frameIntro(t){
    frameParticulas(t);

    // Alas: el trazo aparece, las plumas se llenan y el ala se abre.
    var abre = outBack(tr(t, 980, 1650));
    var aletazo = Math.sin(Math.PI * tr(t, T_ALETAZO, T_ALETAZO + 520)) * (1 - tr(t, T_ALETAZO + 260, T_ALETAZO + 520) * 0.4);
    alas.forEach(function(ala){
      ala.pivote.rotation.set(0, mix(1.25, 0, outCubic(tr(t, 900, 1700))) + aletazo * 0.42, mix(-1.05, 0, abre) + aletazo * 0.3);
      ala.plumas.forEach(function(pl){
        var i = pl.i;
        var tz = tr(t, 820 + i * 70, 1240 + i * 70);
        var ts = tr(t, 1120 + i * 70, 1520 + i * 70);
        pl.mT.opacity = Math.min(1, tz * 1.4) * (1 - 0.7 * ts) + 0.25 * Math.max(0, Math.sin(Math.PI * tr(t, T_ALETAZO - 80, T_ALETAZO + 300)));
        pl.mS.opacity = outCubic(ts);
        pl.mS.emissiveIntensity = 0.35 + 0.9 * Math.max(0, Math.sin(Math.PI * tr(t, T_ALETAZO - 60, T_ALETAZO + 380)));
        pl.pivote.rotation.z = mix(-0.22 * (i + 1), 0, outBack(tr(t, 1000 + i * 60, 1600 + i * 60)));
        var sc = mix(0.55, 1, outCubic(tz));
        pl.pivote.scale.set(sc, sc, 1);
      });
    });

    // Escaner: una linea de luz baja sobre las alas mientras se dibujan.
    var es = tr(t, 820, 1520);
    scan.position.y = mix(280, -220, inOutCubic(es)); scanHalo.position.y = scan.position.y;
    mScan.opacity = Math.sin(Math.PI * es) * 0.9; mScanHalo.opacity = Math.sin(Math.PI * es) * 0.12;

    // Halo: cae girando, parpadea como una senal digital y se asienta.
    var eh = tr(t, 1250, 1880);
    halo.position.y = HALO_Y + mix(560, 0, outBack(eh));
    var sh = mix(0.35, 1, outCubic(eh)); halo.scale.set(sh, sh, sh);
    aro.rotation.z = mix(Math.PI * 7, 0, outQuint(eh)); brillo.rotation.z = aro.rotation.z;
    var glitch = (t > 1250 && t < 1520) ? (Math.random() < 0.32 ? 0.15 : 1) : 1;
    mHalo.opacity = Math.min(1, tr(t, 1250, 1420) * 1.2) * glitch;
    var pulso = Math.max(0, Math.sin(Math.PI * tr(t, 1800, 2300)));
    mBrillo.opacity = (0.18 + 0.5 * pulso) * mHalo.opacity;
    mHalo.emissiveIntensity = 0.45 + 0.9 * pulso;

    // Onda de energia cuando el halo se asienta.
    [[onda1, 1820, 0], [onda2, 1900, 1]].forEach(function(o){
      var u = tr(t, o[1], o[1] + 700);
      o[0].visible = u > 0 && u < 1;
      var r = mix(HALO_R, 1500, outCubic(u));
      o[0].scale.set(r, r * (o[2] ? 0.62 : 0.5), 1);
      o[0].material.opacity = (1 - u) * 0.85;
    });

    // Barrido de luz y camara: de tres cuartos a de frente.
    barrido.position.set(mix(-1800, 1800, tr(t, 600, 1900)), 300, 900);
    var eg = inOutCubic(tr(t, 1250, 2250));
    var tilt = 1 - eg;
    g.rotation.set(0.34 * tilt, -0.62 * tilt, 0.04 * tilt);
    g.scale.setScalar(mix(0.82, 1, outCubic(tr(t, 0, 1400))) * (1 + 0.04 * aletazo));
    g.position.set(0, yRest, 0);
    if(t > 300 && pista && !pista.classList.contains('on')) pista.classList.add('on');
  }

  function fijaReposo(){
    // Todo en su sitio final, por si se salto la animacion.
    for(var i = 0; i < NP; i++){ var j = i * 3; col[j] = 0; col[j + 1] = 0; col[j + 2] = 0; }
    geoP.attributes.color.needsUpdate = true;
    alas.forEach(function(ala){
      ala.pivote.rotation.set(0, 0, 0);
      ala.plumas.forEach(function(pl){ pl.mS.opacity = 1; pl.mT.opacity = 0.18; pl.pivote.rotation.z = 0; pl.pivote.scale.set(1, 1, 1); pl.mS.emissiveIntensity = 0.35; });
    });
    halo.position.y = HALO_Y; halo.scale.set(1, 1, 1); aro.rotation.z = 0; brillo.rotation.z = 0;
    mHalo.opacity = 1; mHalo.emissiveIntensity = 0.45; mBrillo.opacity = 0.18;
    onda1.visible = false; onda2.visible = false; mScan.opacity = 0; mScanHalo.opacity = 0;
    g.rotation.set(0, 0, 0); g.scale.setScalar(1); g.position.set(0, yRest, 0);
  }

  function preparaTraspaso(){
    fijaReposo();
    var cl = ES_STAFF ? destinoStaff() : cajaLogo(document.getElementById('v2-logo-slot'));
    var ch = (!ES_STAFF && contenido && contenido.view === 'hoy') ? centroDe('v2-halo-slot') : null;
    destino = { logo: cl ? { pos: aMundo(cl.x, cl.y), k: (cl.w / s) / LOGO_W } : null,
                halo: ch ? { pos: aMundo(ch.x, ch.y), k: ((ch.w / 2 - 6) / s) / (HALO_R - 9) } : null };
    if(destino.halo){ halo.updateMatrixWorld(true); scene.attach(halo); destino.haloDesde = halo.position.clone(); destino.haloEsc = halo.scale.x; }
    overlay.classList.add('transparente');
    fondo.classList.add('fuera');
    if(pista) pista.classList.remove('on');
    var cuerpo = document.getElementById('v2-cuerpo');
    if(cuerpo) setTimeout(function(){ try { cuerpo.classList.remove('espera'); } catch(e){} }, 300);
  }
  function opacidadAlas(v){
    alas.forEach(function(ala){ ala.plumas.forEach(function(pl){ pl.mS.opacity = v; pl.mT.opacity = 0.18 * v; }); });
  }
  function frameTraspaso(u){
    var e = inOutCubic(u);
    if(destino.logo){
      g.position.set(mix(0, destino.logo.pos.x, e), mix(yRest, destino.logo.pos.y, e), 0);
      g.scale.setScalar(mix(1, destino.logo.k, e));
      opacidadAlas(1 - tr(u, 0.78, 1));
      if(!destino.halo){ mHalo.opacity = 1 - tr(u, 0.78, 1); mBrillo.opacity = 0.18 * (1 - e); }
    } else {
      g.scale.setScalar(mix(1, 0.6, e));
      opacidadAlas(1 - e);
      if(!destino.halo){ mHalo.opacity = 1 - e; mBrillo.opacity = 0.18 * (1 - e); }
    }
    if(destino.halo){
      halo.position.set(mix(destino.haloDesde.x, destino.halo.pos.x, e), mix(destino.haloDesde.y, destino.halo.pos.y, e), 0);
      halo.scale.setScalar(mix(destino.haloEsc, destino.halo.k, e));
      haloIncl.rotation.x = mix(HALO_INCL, 0, e);
      aro.rotation.z = mix(0, Math.PI * 2, e);
      mBrillo.opacity = mix(0.18, 0.5, tr(u, 0.4, 1));
    }
    if(u >= 0.75){ var slot = document.getElementById('v2-logo-slot'); if(slot) slot.classList.add('on'); if(ES_STAFF) staffLogos('on'); }
  }
  function frameSalida(u){
    if(destino.halo){ mHalo.opacity = 1 - u; mBrillo.opacity = 0.5 * (1 - u); }
  }
  function termina(){
    if(terminado) return;
    terminado = true; corriendo = false;
    try {
      window.V2_APERTURA_PENDIENTE = false;
      var slot = document.getElementById('v2-logo-slot'); if(slot){ slot.classList.add('on'); slot.classList.add('fijo'); }
      var haloSlot = document.getElementById('v2-halo-slot'); if(haloSlot) haloSlot.classList.remove('oculto');
      var cuerpo = document.getElementById('v2-cuerpo'); if(cuerpo) cuerpo.classList.remove('espera');
      overlay.classList.remove('on');
      if(ES_STAFF){ staffLogos('on'); raiz.classList.remove('apertura-3d'); }
      try { if(fondo.parentNode) fondo.parentNode.removeChild(fondo); } catch(e){}
      try { if(pista) pista.classList.remove('ang-claro'); } catch(e){}
      renderer.dispose();
    } catch(e){ console.error('apertura fin', e); }
  }
  window.V2_apertura = {
    contenidoListo: function(view){
      try {
        contenido = { view: view, at: performance.now() };
        if(terminado){
          var haloSlot = document.getElementById('v2-halo-slot'); if(haloSlot) haloSlot.classList.remove('oculto');
          var cuerpo = document.getElementById('v2-cuerpo'); if(cuerpo) cuerpo.classList.remove('espera');
          var slot = document.getElementById('v2-logo-slot'); if(slot) slot.classList.add('fijo');
        }
      } catch(e){}
    },
    saltar: function(){ try { if(fase === 'intro') t0 = performance.now() - T_HAND; } catch(e){} }
  };

  function render(){ renderer.render(scene, camera); }
  function loop(now){
    if(!corriendo) return;
    var t = now - t0;
    try {
      if(fase === 'intro'){
        frameIntro(Math.min(t, T_HAND));
        if(t >= T_HAND){
          if(contenido || t >= T_HAND + ESPERA_MAX){ fase = 'traspaso'; tHand = now; preparaTraspaso(); }
        }
      } else if(fase === 'traspaso'){
        var u = clamp01((now - tHand) / DUR_HAND);
        frameTraspaso(u);
        if(u >= 1){
          if(destino.halo){ fase = 'salida'; tHand = now; var hs = document.getElementById('v2-halo-slot'); if(hs) hs.classList.remove('oculto'); }
          else { termina(); return; }
        }
      } else if(fase === 'salida'){
        var v = clamp01((now - tHand) / 260);
        frameSalida(v);
        if(v >= 1){ termina(); return; }
      }
      render();
    } catch(e){ console.error('apertura', e); termina(); return; }
    requestAnimationFrame(loop);
  }
  function arranca(){
    try { if(window.V2_CONTENIDO_VISTA && !contenido) contenido = { view: window.V2_CONTENIDO_VISTA, at: performance.now() }; } catch(e){}
    encuadre();
    overlay.classList.add('on');
    corriendo = true; t0 = performance.now(); frameIntro(0); render(); requestAnimationFrame(loop);
  }
  overlay.addEventListener('pointerdown', function(){ window.V2_apertura.saltar(); });
  document.addEventListener('visibilitychange', function(){ if(document.hidden && !terminado) termina(); });
  if(document.fonts && document.fonts.ready) document.fonts.ready.then(arranca, arranca); else arranca();
} catch(err) {
  console.warn('Apertura 3D no disponible:', err && err.message);
  try { if(window.v2AperturaCancelar) window.v2AperturaCancelar(); } catch(e){}
}
