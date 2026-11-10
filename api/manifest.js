// Angels - manifest por jugador.
// La app instalada desde el enlace personal debe abrir ese mismo enlace, y en
// iPhone solo una app instalada con manifest puede recibir notificaciones.
module.exports = function handler(req, res) {
  var raw = (req.query && req.query.t) ? String(req.query.t) : '';
  var t = raw.replace(/[^A-Za-z0-9]/g, '').slice(0, 128);
  var start = t.length >= 32 ? '/?t=' + t : '/';
  var body = {
    name: 'Angels',
    short_name: 'Angels',
    description: 'Check-in de bienestar y carga de entrenamiento de ADC Angels JV Masculino.',
    id: start,
    start_url: start,
    scope: '/',
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#1B2A6B',
    theme_color: '#1B2A6B',
    lang: 'es-PR',
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
    ]
  };
  res.setHeader('Content-Type', 'application/manifest+json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  res.status(200).send(JSON.stringify(body));
};
