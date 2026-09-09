// Vercel serverless function — échange le code OAuth GitHub contre un access_token
// Variables d'env requises dans Vercel dashboard :
//   GH_CLIENT_ID     = Ov23li7t3A7ZkHgtN7hl
//   GH_CLIENT_SECRET = (ton client secret)

export default async function handler(req, res) {
  // CORS pour Flutter web + Android
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { code } = req.body ?? {};
  if (!code) {
    return res.status(400).json({ error: 'Missing code' });
  }

  const clientId     = process.env.GH_CLIENT_ID;
  const clientSecret = process.env.GH_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    return res.status(500).json({ error: 'Server misconfigured — env vars missing' });
  }

  try {
    const response = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({ client_id: clientId, client_secret: clientSecret, code }),
    });

    const data = await response.json();

    if (data.error) {
      return res.status(400).json({ error: data.error_description ?? data.error });
    }

    return res.status(200).json({ access_token: data.access_token, token_type: data.token_type });
  } catch (err) {
    return res.status(500).json({ error: `Backend error: ${err.message}` });
  }
}
