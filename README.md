# GlowUps demo

AI WhatsApp receptionist for salons. Demo website with sample data.

## Run on localhost

```bash
cd ~/Projects/glowups
./start.sh          # opens http://localhost:8080
./start.sh 3000     # or pick another port
```

If `./start.sh` says "permission denied", run `chmod +x start.sh` once.

## Files

- `index.html` - the GlowUps website: pitch, live WhatsApp chat demo, chair board, pricing, pilot. Dashboards open at `#customer`, `#reception`, `#owner`.
- `sql/001_core.sql` - Supabase schema: tables, indexes, booking functions (slots, hold, confirm) and row level security.
- `salon-app.html` - the standalone salon software (customer, reception, owner views) at http://localhost:8080/salon-app.html

## Notes

- All salon data is generated sample data.
- Bookings and changes are saved in your browser (localStorage) for the current day only.
- The chat uses simple rules in the browser. The real product will use n8n + OpenAI + Supabase.
