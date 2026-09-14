const admin = require('firebase-admin');

// Initialize with project service account
const serviceAccount = require('./easy-market-96c4a-firebase-adminsdk-fbsvc-3b73f5b9e6.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

const vendors = [
  {
    company_name: 'TechStore Pro',
    full_name: 'Jean Mukendi',
    email: 'techstore@aisy.com',
    phone: '+243811111111',
    commune: 'Gombe',
    localisation: 'Kinshasa, Gombe',
    latitude: -4.309,
    longitude: 15.315,
    products_count: 5,
    rating: 4.8,
    plan: 'premium',
    subscription_status: 'active',
    verified: true,
    photo: 'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'FashionHub',
    full_name: 'Marie Kabongo',
    email: 'fashion@aisy.com',
    phone: '+243822222222',
    commune: 'Ngaliema',
    localisation: 'Kinshasa, Ngaliema',
    latitude: -4.341,
    longitude: 15.261,
    products_count: 3,
    rating: 4.3,
    plan: 'premium',
    subscription_status: 'active',
    verified: true,
    photo: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'Maison & Deco',
    full_name: 'Pierre Tshilombo',
    email: 'deco@aisy.com',
    phone: '+243833333333',
    commune: 'Limete',
    localisation: 'Kinshasa, Limete',
    latitude: -4.363,
    longitude: 15.345,
    products_count: 2,
    rating: 4.5,
    plan: 'free',
    subscription_status: 'active',
    verified: false,
    photo: 'https://images.unsplash.com/photo-1508214751196-bcfd4ca60f91?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'ElectroDiscount',
    full_name: 'David Kasongo',
    email: 'electro@aisy.com',
    phone: '+243844444444',
    commune: 'Kalamu',
    localisation: 'Kinshasa, Kalamu',
    latitude: -4.331,
    longitude: 15.320,
    products_count: 8,
    rating: 4.1,
    plan: 'free',
    subscription_status: 'active',
    verified: false,
    photo: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'Bio Market',
    full_name: 'Grace Lukusa',
    email: 'bio@aisy.com',
    phone: '+243855555555',
    commune: 'Bandal',
    localisation: 'Kinshasa, Bandalungwa',
    latitude: -4.321,
    longitude: 15.290,
    products_count: 6,
    rating: 4.6,
    plan: 'premium',
    subscription_status: 'active',
    verified: true,
    photo: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'Casa Electronics',
    full_name: 'Samuel Kalala',
    email: 'casa@aisy.com',
    phone: '+243866666666',
    commune: 'Matete',
    localisation: 'Kinshasa, Matete',
    latitude: -4.338,
    longitude: 15.305,
    products_count: 12,
    rating: 4.7,
    plan: 'premium',
    subscription_status: 'active',
    verified: true,
    photo: 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
  {
    company_name: 'Mode Africa',
    full_name: 'Chantal Mbuyi',
    email: 'modeafrica@aisy.com',
    phone: '+243877777777',
    commune: 'Barumbu',
    localisation: 'Kinshasa, Barumbu',
    latitude: -4.315,
    longitude: 15.328,
    products_count: 15,
    rating: 4.9,
    plan: 'premium',
    subscription_status: 'active',
    verified: true,
    photo: 'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=200&h=200&fit=crop',
    role: 'vendeur',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  },
];

async function seed() {
  const batch = db.batch();
  for (const v of vendors) {
    // Use email as doc ID to avoid duplicates
    const docId = v.email.replace(/[@.]/g, '_');
    const ref = db.collection('vendeurs').doc(docId);
    batch.set(ref, v, { merge: true });
  }
  await batch.commit();
  console.log(`${vendors.length} vendors seeded to Firestore!`);
  process.exit(0);
}

seed().catch(e => { console.error(e); process.exit(1); });
