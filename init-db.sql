-- Initialize databases for Taler PoC

-- Create databases
CREATE DATABASE taler_exchange;
CREATE DATABASE taler_merchant;
CREATE DATABASE taler_bank;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE taler_exchange TO taler;
GRANT ALL PRIVILEGES ON DATABASE taler_merchant TO taler;
GRANT ALL PRIVILEGES ON DATABASE taler_bank TO taler;
