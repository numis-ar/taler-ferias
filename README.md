# GNU Taler Payment System - Minimal Proof of Concept

This is a minimal proof of concept setup for the [GNU Taler](https://taler.net/) payment system, an anonymous, taxable electronic payment system.

## What is GNU Taler?

GNU Taler is a free software payment system that provides:
- **Privacy for customers**: Payments are anonymous
- **Transparency for merchants**: Income is visible for taxation
- **Security**: Cryptographically secured transactions
- **Compatibility**: Works with traditional banking systems

## Architecture

This PoC includes the following components:

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
│  Demo Frontend  │────▶│ Merchant Backend │────▶│ Taler Demo Exchange      │
│  (Port 8080)    │     │  (Port 9966)     │     │ https://exchange.demo.   │
└─────────────────┘     └──────────────────┘     │ taler.net/               │
                                                 │ (KUDOS test currency)    │
                                                 └──────────────────────────┘
```

### Components

1. **Taler Demo Exchange**: The public demonstration exchange at https://exchange.demo.taler.net/ 
   - Issues and redeems digital KUDOS currency
   - Connected to the demo bank at https://bank.demo.taler.net/

2. **Merchant Backend** (Port 9966): Handles merchant operations and order processing
   - Web UI at http://localhost:9966/webui/
   - Admin login: `admin` / `adminpassword`

3. **Demo Frontend** (Port 8080): A simple HTML/JavaScript frontend
   - Redirects to the Merchant Web UI for order creation

4. **PostgreSQL**: Database for storing merchant data

## Quick Start (Docker - Recommended)

### Option 1: Automated Subdomain Deployment (Recommended for Servers)

Use the `install-taler.sh` script to deploy on a subdomain with SSL:

```bash
# 1. Clone the repository
git clone https://github.com/numis-ar/taler-ferias.git
cd taler-ferias

# 2. Run the install script with your full domain
sudo ./install-taler.sh shop.example.com
# or
sudo ./install-taler.sh myapp.staging.yourdomain.org
```

The script will:
- Deploy to `https://shop.example.com` (or your domain)
- Set up Nginx with SSL (Let's Encrypt)
- Configure dynamic ports to avoid conflicts
- Start all services automatically

**Prerequisites:**
- Docker and Docker Compose installed
- Nginx installed
- DNS pointing your subdomain to the server
- Ports 80/443 available for Nginx (or use direct ports mode)

**Access your deployment:**
- Demo Store: `https://shop.example.com`
- Merchant Admin: `https://shop.example.com/webui/`
- Login: `admin` / `adminpassword`

### Option 2: Local Development

1. Build and start all services:
```bash
docker compose up -d
```

2. Access the demo frontend at http://localhost:8080

3. Access the Merchant Web UI at http://localhost:9966/webui/
   - Login: `admin` / `adminpassword`

4. View logs:
```bash
docker compose logs -f
```

5. Stop all services:
```bash
docker compose down
```

### Option 3: Local Installation (Ubuntu 24.04)

1. Run the installation script:
```bash
chmod +x install-local.sh
./install-local.sh
```

2. Start the Taler services:
```bash
~/start-taler.sh
```

3. In a new terminal, start the demo frontend:
```bash
cd /home/didi/code/taler-fullsystem
python3 -m http.server 8080
```

4. Open your browser to http://localhost:8080

## Testing the Payment Flow

### Using the Demo Bank (KUDOS)

1. **Install a Taler Wallet**:
   - Browser extension: Available for Firefox/Chrome at https://wallet.taler.net/
   - CLI wallet: Install `taler-wallet-cli` package

2. **Get Test Currency**:
   - Visit the public demo at https://bank.demo.taler.net/
   - Create a test account and withdraw KUDOS into your wallet

3. **Create an Order (via Merchant Web UI)**:
   - Visit http://localhost:9966/webui/
   - Login with: `admin` / `adminpassword`
   - Click on "Orders" in the left menu
   - Click "+" to create a new order
   - Set amount (e.g., 5.00) and currency (KUDOS)
   - Add a summary (e.g., "Coffee")
   - Click "Create Order"
   - Copy the order link or click to open it

4. **Make a Purchase**:
   - Open the order link
   - The Taler wallet will open automatically
   - Confirm the payment
   - The merchant will receive the funds instantly!

### Alternative: Using the Demo Frontend

1. Visit http://localhost:8080
2. Click "Buy Now" on any product
3. This opens the Merchant Web UI in a new tab
4. Login with `admin` / `adminpassword`
5. Create the order as described above

## API Endpoints

### Merchant Backend API

| Endpoint | Description |
|----------|-------------|
| `GET /config` | Get merchant configuration |
| `GET /webui/` | Merchant Web UI (admin interface) |
| `POST /private/orders` | Create a new order (requires auth) |

### Exchange API (Demo)

| Endpoint | Description |
|----------|-------------|
| `GET https://exchange.demo.taler.net/keys` | Get exchange public keys |
| `POST /reserve/withdraw` | Withdraw coins |
| `POST /deposit` | Deposit coins |

## Configuration Files

- `/etc/taler/taler-exchange.conf` - Exchange configuration
- `/etc/taler/taler-merchant.conf` - Merchant configuration
- `docker-compose.yml` - Docker deployment configuration

## Troubleshooting

### PostgreSQL Issues

If PostgreSQL fails to start:
```bash
sudo systemctl start postgresql
sudo -u postgres psql -c "CREATE USER taler WITH PASSWORD 'talerpassword' CREATEDB;"
```

### Port Conflicts

If ports are already in use, modify the configuration files to use different ports.

### Database Initialization

Reset databases:
```bash
sudo -u postgres dropdb taler_exchange taler_merchant taler_bank
sudo -u postgres createdb taler_exchange taler_merchant taler_bank
```

### "No active bank accounts configured" Error

If you see this error when creating orders, the merchant needs a bank account:

```bash
# Add a bank account via SQL
docker compose exec postgres psql -U taler -d taler_merchant -c "
INSERT INTO merchant.merchant_accounts 
  (merchant_serial, h_wire, salt, payto_uri, active)
VALUES 
  (1, 
   decode('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef', 'hex'), 
   decode('0123456789abcdef0123456789abcdef', 'hex'),
   'payto://x-taler-bank/localhost:8082/admin',
   true);
"
```

## Automated Deployment Script

The `install-taler.sh` script automates deployment to a server:

### Usage

```bash
sudo ./install-taler.sh <full-domain>
```

### Examples

```bash
# Simple subdomain
sudo ./install-taler.sh shop.example.com

# Nested subdomain
sudo ./install-taler.sh pay.app.staging.example.org

# Multiple instances (different ports automatically assigned)
sudo ./install-taler.sh shop1.example.com
sudo ./install-taler.sh shop2.example.com
```

### What the Script Does

1. **Clones repository** to `/opt/taler-<subdomain>`
2. **Generates unique ports** based on subdomain hash (avoids conflicts)
3. **Creates Nginx config** with SSL redirect
4. **Obtains SSL certificate** via Let's Encrypt (or falls back to HTTP)
5. **Starts Docker services** with docker-compose
6. **Configures firewall** for the assigned ports

### Troubleshooting Automated Deployment

**SSL Certificate Issues:**
- Ensure DNS is properly configured before running
- The script will fall back to HTTP-only if SSL fails
- Retry later with: `sudo certbot --nginx -d your.domain.com`

**Port Conflicts:**
- The script automatically assigns unique ports per instance
- Check assigned ports in the output
- Internal ports are exposed at `0.0.0.0:<port>` for Nginx proxying

**Docker Compose Errors:**
- Ensure Docker and Docker Compose (v2 plugin or standalone) are installed
- Check `docker compose version` or `docker-compose version`

## Security Notes

⚠️ **This is a proof of concept setup and NOT suitable for production use!**

- Uses test currency (KUDOS) with no real value
- Fake bank is for testing only
- Configuration uses weak passwords (`admin`/`adminpassword`)
- SSL/TLS is recommended but optional (for local testing)
- No proper access controls

For production deployment, see the [official Taler documentation](https://docs.taler.net/).

## Useful Commands

```bash
# Check exchange status
curl http://localhost:8081/keys | jq

# Check merchant config
curl http://localhost:9966/config | jq

# View PostgreSQL databases
sudo -u postgres psql -l

# View exchange logs
journalctl -u taler-exchange -f

# View merchant logs
journalctl -u taler-merchant -f
```

## Resources

- [GNU Taler Website](https://taler.net/)
- [Official Documentation](https://docs.taler.net/)
- [Taler Wallet](https://wallet.taler.net/)
- [Demo Bank](https://bank.demo.taler.net/)

## License

This PoC setup is provided as-is for educational and testing purposes.
GNU Taler itself is licensed under various free software licenses (GPL, AGPL, etc.).
