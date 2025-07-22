# Secret References

## Home Assistant
- `homeassistant-secrets` in `automation` namespace
  - `secret-key`: HA secret key for encryption
  - `db-password`: Database password (if using external DB)

## 1Password Items Required
- `homeassistant`: Contains secret_key field
- `homeassistant-db`: Contains password field (if using external DB)
