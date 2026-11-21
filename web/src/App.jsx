import { useEffect, useState } from 'react';
import { cartToItems, cartTotal, formatPrice, groupByStatus } from './lib.js';

const VERSION = import.meta.env.VITE_GIT_COMMIT || 'dev';

const TABS = [
  { key: 'order', label: 'Order', icon: '🍽️' },
  { key: 'kitchen', label: 'Kitchen', icon: '👨‍🍳' },
  { key: 'stats', label: 'Stats', icon: '📊' },
];

const COLUMNS = [
  { key: 'new', title: 'New orders', subtitle: 'Waiting to be prepared' },
  { key: 'cooking', title: 'Cooking', subtitle: 'Being prepared now' },
  { key: 'ready', title: 'Ready', subtitle: 'Ready to serve' },
];

const CATEGORIES = [
  'All',
  'Karahi & Handi',
  'Rice & Biryani',
  'BBQ & Grill',
  'Traditional Desi',
  'Breads & Sides',
  'Drinks',
];

const FOOD = {
  'Chicken Karahi': ['Karahi & Handi', 'A classic dhaba favourite with tender chicken, tomatoes, ginger and green chillies.', '/images/menu/chicken-karahi.jpg'],
  'Mutton Karahi': ['Karahi & Handi', 'Slow-cooked mutton tossed with fresh tomatoes, ginger and aromatic spices.', '/images/menu/mutton-karahi.jpg'],
  'Chicken White Karahi': ['Karahi & Handi', 'Creamy, mildly spiced chicken karahi finished with ginger and green chillies.', '/images/menu/chicken-white-karahi.jpg'],
  'Chicken Handi': ['Karahi & Handi', 'Rich handi-style chicken cooked in a smooth, flavourful masala.', '/images/menu/chicken-handi.jpg'],
  Biryani: ['Rice & Biryani', 'Fragrant basmati rice layered with spiced chicken and served hot.', '/images/menu/pakistani-biryani.jpg'],
  'Beef Pulao': ['Rice & Biryani', 'Aromatic rice cooked with tender beef and traditional whole spices.', 'photo-1589302168068-964664d93dc0'],
  'Chicken Pulao': ['Rice & Biryani', 'Lightly spiced chicken pulao with fragrant rice and warming stock.', '/images/menu/chicken-pulao.jpg'],
  'Special Dhaba Biryani': ['Rice & Biryani', 'Our signature-style biryani with bold spices and a generous serving.', '/images/menu/pakistani-biryani.jpg'],
  'Chicken Tikka': ['BBQ & Grill', 'Marinated chicken grilled until smoky, juicy and lightly charred.', '/images/menu/chicken-tikka.jpg'],
  'Chicken Malai Boti': ['BBQ & Grill', 'Tender chicken pieces in a creamy marinade, grilled over high heat.', '/images/menu/chicken-malai-boti.jpg'],
  'Beef Seekh Kebab': ['BBQ & Grill', 'Seasoned minced beef shaped on skewers and grilled with smoky flavour.', '/images/menu/seekh-kebab.jpg'],
  'Chicken Seekh Kebab': ['BBQ & Grill', 'Juicy chicken seekh kebab with a balanced blend of herbs and spices.', '/images/menu/seekh-kebab.jpg'],
  'Daal Tadka': ['Traditional Desi', 'Comforting lentils finished with a fragrant garlic and spice tempering.', '/images/menu/daal-tadka.jpg'],
  'Chana Masala': ['Traditional Desi', 'Chickpeas simmered in a tangy, warmly spiced tomato masala.', '/images/menu/chana-masala.jpg'],
  'Aloo Palak': ['Traditional Desi', 'Potatoes and spinach cooked together with everyday desi spices.', 'photo-1547592180-85f173990554'],
  'Mix Vegetable': ['Traditional Desi', 'Seasonal vegetables cooked in a homestyle masala.', '/images/menu/mixed-vegetable-curry.jpg'],
  'Garlic Naan': ['Breads & Sides', 'Soft tandoor-baked naan finished with garlic and a light butter glaze.', '/images/menu/garlic-naan.jpg'],
  'Roghni Naan': ['Breads & Sides', 'A soft, slightly rich naan topped with sesame seeds.', '/images/menu/roghni-naan.jpg'],
  'Tandoori Roti': ['Breads & Sides', 'Freshly baked whole-wheat roti from the tandoor.', '/images/menu/tandoori-roti.jpg'],
  Raita: ['Breads & Sides', 'Cool yoghurt with cucumber and a gentle touch of seasoning.', '/images/menu/mint-raita.jpg'],
  'Mango Lassi': ['Drinks', 'A chilled, creamy yoghurt drink blended with sweet mango.', '/images/menu/mango-lassi.jpg'],
  'Sweet Lassi': ['Drinks', 'Traditional chilled yoghurt drink, smooth and refreshing.', 'photo-1572490122747-3968b75cc699'],
  'Mint Lemonade': ['Drinks', 'A refreshing blend of lemon, mint and chilled water.', 'photo-1551024709-8f23befc6f87'],
  'Soft Drink': ['Drinks', 'A chilled bottled soft drink served cold.', 'photo-1551024709-8f23befc6f87'],
};

function imageUrl(photo) {
  if (typeof photo === 'string' && photo.startsWith('/')) return photo;
  return `https://images.unsplash.com/${photo}?auto=format&fit=crop&w=900&q=82`;
}

function usePolling(url, intervalMs) {
  const [data, setData] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        if (active) {
          setData(json);
          setFailed(false);
        }
      } catch {
        if (active) setFailed(true);
      }
    };
    load();
    const timer = setInterval(load, intervalMs);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [url, intervalMs]);

  return { data, failed };
}

function OrderPage() {
  const { data: menu, failed } = usePolling('/api/menu', 30000);
  const [cart, setCart] = useState({});
  const [message, setMessage] = useState(null);
  const [busy, setBusy] = useState(false);
  const [category, setCategory] = useState('All');
  const [search, setSearch] = useState('');

  const dishes = (menu ?? []).map((dish) => ({
    ...dish,
    category: FOOD[dish.name]?.[0] ?? 'Traditional Desi',
    description: FOOD[dish.name]?.[1] ?? 'Freshly prepared with care and traditional flavours.',
    photo: FOOD[dish.name]?.[2] ?? 'photo-1547592180-85f173990554',
  }));

  const filtered = dishes.filter((dish) => {
    const matchesCategory = category === 'All' || dish.category === category;
    const term = search.trim().toLowerCase();
    return matchesCategory && (!term || `${dish.name} ${dish.description}`.toLowerCase().includes(term));
  });

  const items = cartToItems(cart);
  const total = cartTotal(cart, dishes);
  const itemCount = items.reduce((sum, item) => sum + item.qty, 0);

  const change = (name, delta) => {
    setCart((current) => ({
      ...current,
      [name]: Math.max(0, (current[name] ?? 0) + delta),
    }));
  };

  const placeOrder = async () => {
    setBusy(true);
    setMessage(null);
    try {
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? body.detail ?? 'The order could not be placed');
      setCart({});
      setMessage({ ok: true, text: `Order #${body.id} has been sent to the kitchen. Thank you!` });
    } catch (err) {
      setMessage({ ok: false, text: err.message });
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <section className="hero">
        <div className="hero-copy">
          <span className="eyebrow">AUTHENTIC PAKISTANI FLAVOUR</span>
          <h1>Good food.<br /><em>Great memories.</em></h1>
          <p>From sizzling karahi to fragrant biryani, discover the taste of a proper dhaba — freshly prepared and served with heart.</p>
          <a className="hero-cta" href="#menu">Explore the menu <span>↓</span></a>
          <div className="hero-trust"><span>✦ Freshly prepared</span><span>✦ Made with care</span></div>
        </div>
        <div className="hero-photo" role="img" aria-label="Pakistani food spread">
          <div className="hero-stamp"><strong>100%</strong><span>Desi taste</span></div>
        </div>
      </section>

      <div className="welcome-strip">
        <span>🥘 Homestyle cooking</span><span>🔥 Fresh from the kitchen</span><span>🇵🇰 Proudly desi</span>
      </div>

      <section id="menu" className="menu-section">
        <div className="section-heading">
          <div><span className="eyebrow">MADE FRESH FOR YOU</span><h2>Explore our menu</h2><p className="muted">Your favourites, prepared the dhaba way.</p></div>
          <span className="menu-count">{dishes.length} dishes · PKR</span>
        </div>

        <div className="menu-tools">
          <div className="category-list" aria-label="Filter menu by category">
            {CATEGORIES.map((item) => (
              <button key={item} type="button" className={category === item ? 'category-chip active' : 'category-chip'} onClick={() => setCategory(item)}>{item}</button>
            ))}
          </div>
          <label className="search-box"><span>⌕</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search dishes..." aria-label="Search dishes" /><kbd>⌘ K</kbd></label>
        </div>

        {failed && <p className="notice bad">The menu could not be loaded. Retrying automatically.</p>}
        {!menu && !failed && <p className="muted loading-text">Preparing the menu...</p>}
        {menu && filtered.length === 0 && <p className="empty-results">No dishes match your search. Try another name or category.</p>}

        <div className="order-layout">
          <section className="menu-grid" aria-label="Restaurant menu">
            {filtered.map((dish) => {
              const quantity = cart[dish.name] ?? 0;
              return (
                <article className={`menu-card ${quantity > 0 ? 'selected' : ''}`} key={dish.id}>
                  <div className="dish-photo">
                    <img src={imageUrl(dish.photo)} alt={dish.name} loading="lazy" />
                    <span className="dish-category">{dish.category}</span>
                    {quantity > 0 && <span className="selected-tag">In your order</span>}
                  </div>
                  <div className="dish-info">
                    <h3>{dish.name}</h3>
                    <p className="dish-description">{dish.description}</p>
                    <div className="dish-bottom">
                      <strong className="price">{formatPrice(dish.price)}</strong>
                      <div className="stepper">
                        <button type="button" aria-label={`Remove one ${dish.name}`} disabled={quantity === 0} onClick={() => change(dish.name, -1)}>−</button>
                        <output aria-label={`${quantity} ${dish.name} selected`}>{quantity}</output>
                        <button type="button" aria-label={`Add one ${dish.name}`} onClick={() => change(dish.name, 1)}>+</button>
                      </div>
                    </div>
                  </div>
                </article>
              );
            })}
          </section>

          <aside className="ticket">
            <div className="ticket-heading"><div><span className="eyebrow">YOUR SELECTION</span><h2>Your order</h2></div><span className="cart-icon">🛍️</span></div>
            <div className="cart-count">{itemCount} {itemCount === 1 ? 'item' : 'items'} selected</div>
            {items.length === 0 ? (
              <div className="empty-cart"><span>🥡</span><strong>Your cart is waiting</strong><p>Add something delicious from the menu to get started.</p></div>
            ) : (
              <ul className="cart-items">
                {items.map((item) => {
                  const dish = dishes.find((entry) => entry.name === item.name);
                  return <li key={item.name}><div><strong>{item.name}</strong><span>{formatPrice(dish?.price ?? 0)} each</span></div><div className="cart-controls"><button type="button" aria-label={`Remove one ${item.name}`} onClick={() => change(item.name, -1)}>−</button><b>{item.qty}</b><button type="button" aria-label={`Add one ${item.name}`} onClick={() => change(item.name, 1)}>+</button></div></li>;
                })}
              </ul>
            )}
            <div className="ticket-total"><span>Subtotal</span><strong>{formatPrice(total)}</strong></div>
            <p className="secure-note">Final bill is based on selected menu prices. Delivery charges, if any, are not included.</p>
            <button type="button" className="primary" disabled={busy || items.length === 0} onClick={placeOrder}>{busy ? 'Placing order...' : 'Place your order'} <span>→</span></button>
            {message && <p className={`notice ${message.ok ? 'good' : 'bad'}`} role="status">{message.text}</p>}
          </aside>
        </div>
      </section>
    </>
  );
}

function KitchenPage() {
  const { data, failed } = usePolling('/api/orders', 2000);
  const groups = groupByStatus(data ?? []);
  return (
    <section className="dashboard-page">
      <div className="section-heading"><div><span className="eyebrow">LIVE ORDER MANAGEMENT</span><h2>Kitchen dashboard</h2><p className="muted">Keep track of orders as they move through the kitchen.</p></div><span className="live-indicator"><span /> Live updates</span></div>
      {failed && <p className="notice bad">Orders could not be loaded. Retrying.</p>}
      <div className="rail">
        {COLUMNS.map((column) => (
          <div key={column.key} className={`lane ${column.key}`}>
            <div className="lane-heading"><div><h3>{column.title}</h3><p>{column.subtitle}</p></div><span className="count">{groups[column.key].length}</span></div>
            {groups[column.key].length === 0 && <p className="lane-empty">No orders here yet.</p>}
            {groups[column.key].map((order) => <article key={order.id} className="slip"><div className="slip-heading"><strong>Order #{order.id}</strong><span>{order.items.length} dishes</span></div><ul>{order.items.map((item) => <li key={item.name}><span>{item.name}</span><strong>× {item.qty}</strong></li>)}</ul></article>)}
          </div>
        ))}
      </div>
    </section>
  );
}

function StatsPage() {
  const { data, failed } = usePolling('/api/stats', 3000);
  return (
    <section className="dashboard-page">
      <div className="section-heading"><div><span className="eyebrow">RESTAURANT OVERVIEW</span><h2>Sales & activity</h2><p className="muted">A quick look at recent restaurant activity.</p></div><span className="live-indicator"><span /> Live updates</span></div>
      {failed && <p className="notice bad">Stats could not be loaded. Retrying.</p>}
      {data && <>
        <div className="numbers">
          <article className="stat-card"><span className="stat-icon">⚡</span><p>Orders this minute</p><strong>{data.orders_this_minute}</strong><span className="stat-caption">Current activity</span></article>
          <article className="stat-card"><span className="stat-icon">🧾</span><p>Orders in last 5 minutes</p><strong>{data.orders_last_5_minutes}</strong><span className="stat-caption">Recent order volume</span></article>
        </div>
        <div className="top-dishes-panel"><div className="panel-heading"><div><span className="eyebrow">CUSTOMER FAVOURITES</span><h3>Top dishes</h3></div><span>🍽️</span></div>
          {data.top_dishes.length === 0 ? <p className="muted">No orders yet. Your bestsellers will appear here.</p> : <ol className="top">{data.top_dishes.map((dish, index) => <li key={dish.name}><span className="rank">{index + 1}</span><span className="top-dish-name">{dish.name}</span><strong>{dish.count} sold</strong></li>)}</ol>}
        </div>
      </>}
      {!data && !failed && <p className="muted loading-text">Loading restaurant statistics...</p>}
    </section>
  );
}

export default function App() {
  const [tab, setTab] = useState('order');
  return (
    <div className="app-shell">
      <header className="site-header">
        <a className="brand" href="#top" onClick={() => setTab('order')}><span className="brand-mark">D</span><span><strong>Dhaba</strong><small>THE FOOD CORNER</small></span></a>
        <nav aria-label="Pages">{TABS.map((item) => <button key={item.key} type="button" aria-current={tab === item.key ? 'page' : undefined} onClick={() => setTab(item.key)}><span>{item.icon}</span>{item.label}</button>)}</nav>
        <span className="header-tag">GOOD FOOD, GOOD TIMES</span>
      </header>
      <main className="page" id="top">
        {tab === 'order' && <OrderPage />}
        {tab === 'kitchen' && <KitchenPage />}
        {tab === 'stats' && <StatsPage />}
      </main>
      <footer className="site-footer"><div><strong>Dhaba</strong><span>Serving happiness, one dish at a time.</span></div><span>Version {VERSION} · Prices in PKR</span></footer>
    </div>
  );
}
