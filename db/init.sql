-- Schema and sample data for Dhaba Orders (no secrets in here).
CREATE TABLE IF NOT EXISTS menu (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price NUMERIC(8,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
  id         SERIAL PRIMARY KEY,
  items      JSONB NOT NULL,
  status     TEXT NOT NULL DEFAULT 'new',  -- new | cooking | ready
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO menu (name, price)
SELECT v.name, v.price
FROM (VALUES
  ('Chicken Karahi', 1250.00),
  ('Mutton Karahi', 2400.00),
  ('Chicken White Karahi', 1450.00),
  ('Chicken Handi', 1400.00),
  ('Biryani', 450.00),
  ('Beef Pulao', 550.00),
  ('Chicken Pulao', 450.00),
  ('Special Dhaba Biryani', 600.00),
  ('Chicken Tikka', 450.00),
  ('Chicken Malai Boti', 650.00),
  ('Beef Seekh Kebab', 350.00),
  ('Chicken Seekh Kebab', 300.00),
  ('Daal Tadka', 350.00),
  ('Chana Masala', 300.00),
  ('Aloo Palak', 350.00),
  ('Mix Vegetable', 400.00),
  ('Garlic Naan', 100.00),
  ('Roghni Naan', 120.00),
  ('Tandoori Roti', 40.00),
  ('Raita', 100.00),
  ('Mango Lassi', 220.00),
  ('Sweet Lassi', 180.00),
  ('Mint Lemonade', 180.00),
  ('Soft Drink', 120.00)
) AS v(name, price)
WHERE NOT EXISTS (SELECT 1 FROM menu);
