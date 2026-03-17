const express = require('express');
const router = express.Router();
const Table = require('../models/Table');
const User = require('../models/User');
const { requireAuth } = require('../middleware/auth');
const upload = require('../config/upload'); // użyjemy tego samego algorytmu multiera
const { toRestaurantSlug } = require('../utils/publicMenu');

// GET /qr (strona główna QR)
router.get('/', requireAuth, async (req, res) => {
    try {
        const tables = await Table.find({ restaurantId: req.session.userId }).sort({ createdAt: -1 });
        const user = await User.findById(req.session.userId);

        res.render('qr', {
            title: 'Kody QR | QResto',
            activePage: '/qr',
            tables: tables, // pętla bazy danych
            user: user    // dostęp do user.logo
        });
    } catch (error) {
        console.error('Błąd pobierania stolików:', error);
        res.status(500).send('Wystąpił błąd serwera');
    }
});

// POST /qr (dodanie nowego stolika)
router.post('/', requireAuth, async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) throw new Error('Podaj nazwę stolika!');

        // Pobierz dane usera z bazy zeby miec jego restaurantName
        const user = await User.findById(req.session.userId);
        if (!user) throw new Error('Nie znaleziono użytkownika');

        // Generowanie stałego linku na subdomenie restauracji (np. pizzeria.qresto.xyz/?table=Stolik-1)
        const protocol = (req.get('x-forwarded-proto') || req.protocol || 'https').split(',')[0].trim();
        const restaurantSlug = toRestaurantSlug(user.restaurantName);
        const rootDomain = (process.env.ROOT_DOMAIN || '').trim();

        const link = rootDomain && restaurantSlug
            ? `${protocol}://${restaurantSlug}.${rootDomain}/?table=${encodeURIComponent(name)}`
            : `${req.protocol}://${req.get('host')}/menu/${encodeURIComponent(restaurantSlug || user.restaurantName.toLowerCase().replace(/\s+/g, '-'))}?table=${encodeURIComponent(name)}`;

        const newTable = new Table({
            restaurantId: req.session.userId,
            name: name,
            link: link
        });

        await newTable.save();
        res.redirect('/qr');
    } catch (error) {
        console.error('Błąd tworzenia stolika:', error);
        req.session.error = error.message;
        res.redirect('/qr');
    }
});



// POST /qr/logo (wrywanie na serwer logotypu dla QR kodu środka)
router.post('/logo', requireAuth, (req, res) => {
    upload.single('logo')(req, res, async (err) => {
        if (err) {
            console.error('Błąd przesyłania logo:', err);
            req.session.error = err.message === 'File too large' ? 'Plik loga jest za duży (maks. 5MB)' : err.message;
            return res.redirect('/qr');
        }

        try {
            if (!req.file) throw new Error('Wybierz plik ze zdjęciem logotypu!');

            const user = await User.findById(req.session.userId);
            // Nadpisujemy stare logo nowo wrzuconym plikiem
            user.logo = `/uploads/menu/${req.session.userId}/${req.file.filename}`;
            await user.save();

            res.redirect('/qr');
        } catch (error) {
            console.error('Błąd zapisu logotypu:', error);
            req.session.error = error.message;
            res.redirect('/qr');
        }
    });
});

// POST /qr/logo/delete (usuwanie logotypu)
router.post('/logo/delete', requireAuth, async (req, res) => {
    try {
        const user = await User.findById(req.session.userId);
        if (user) {
            user.logo = '';
            await user.save();
        }
        res.redirect('/qr');
    } catch (error) {
        console.error('Błąd usuwania logotypu:', error);
        req.session.error = 'Nie udało się usunąć logotypu.';
        res.redirect('/qr');
    }
});



// POST /qr/:id/delete (usunięcie stolika) - MUSI BYĆ NA KOŃCU, ŻEBY NIE PRZECHWYCIŁO /logo/delete
router.post('/:id/delete', requireAuth, async (req, res) => {
    try {
        await Table.findOneAndDelete({
            _id: req.params.id,
            restaurantId: req.session.userId
        });
        res.redirect('/qr');
    } catch (error) {
        console.error('Błąd usuwania stolika:', error);
        req.session.error = 'Nie udało się usunąć stolika.';
        res.redirect('/qr');
    }
});

module.exports = router;
