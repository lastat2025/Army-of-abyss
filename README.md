# Army-of-abyss 🚀

## 🚀 One-Click Railway Deployment (Recommended)

1. [Create a Railway account](https://railway.app/)
2. [Link your GitHub repo](https://railway.app/dashboard)
3. Add the following secrets in your Railway project:
   - `RAILWAY_TOKEN` — Get from Railway dashboard
   - `RAILWAY_PROJECT_ID` — Get from Railway dashboard
   - `DATABASE_URL` — Provided by Railway PostgreSQL plugin
   - `PAYMENT_WALLET` — Your ETH wallet address
   - Any other environment variables needed (see `.env.example` if present)
4. Push to `main` — automatic build & deploy!

## Local Development

```bash
npm install
npm run dev
```

## Production Build

```bash
npm run build
npm start
```

## Docker

```bash
docker build -t army-of-abyss .
docker run -p 3000:3000 army-of-abyss
```

## Environment Variables

- `DATABASE_URL` — PostgreSQL connection string
- `PAYMENT_WALLET` — ETH wallet address for NFT payments

---

_PWA, NFT, and database ready. Battle in the Abyss!_