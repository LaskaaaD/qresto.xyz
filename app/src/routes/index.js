const express = require('express');
const router = express.Router();
const { requireAuth } = require('../middleware/auth');
const Menu = require('../models/Menu');
const Table = require('../models/Table');
const User = require('../models/User');
const { getRestaurantSubdomain, restaurantSlugToRegex } = require('../utils/publicMenu');

router.get('/', async (req, res) => {
    const restaurantSubdomain = getRestaurantSubdomain(req);

    if (!restaurantSubdomain) {
        return res.render('index', { title: 'QResto - Cyfrowe Menu dla Twojej Restauracji' });
    }

    try {
        const user = await User.findOne({
            restaurantName: { $regex: restaurantSlugToRegex(restaurantSubdomain) }
        });

        if (!user) {
            return res.status(404).render('public-menu', {
                restaurantName: 'Nie znaleziono restauracji',
                menu: null
            });
        }

        const menu = await Menu.findOne({ restaurantId: user._id });

        return res.render('public-menu', {
            restaurantName: user.restaurantName,
            menu
        });
    } catch (error) {
        console.error('Błąd pobierania publicznego menu po subdomenie:', error);
        return res.status(500).send('Wystąpił błąd podczas wczytywania menu.');
    }
});

router.get('/login', (req, res) => {
    res.redirect('/auth/login');
});

router.get('/register', (req, res) => {
    res.redirect('/auth/register');
});

router.get('/dashboard', requireAuth, async (req, res) => {
    try {
        // Oblicz ilosc kodów QR (Table)
        const tablesCount = await Table.countDocuments({ restaurantId: req.session.userId });

        // Oblicz ilosc potraw
        let itemsCount = 0;
        const menu = await Menu.findOne({ restaurantId: req.session.userId });
        if (menu && menu.categories) {
            menu.categories.forEach(cat => {
                itemsCount += cat.items.length;
            });
        }

        res.render('dashboard', {
            title: 'Panel Zarządzania (MVP) | QResto',
            activePage: '/dashboard',
            stats: {
                qrCount: tablesCount,
                itemsCount: itemsCount
            },
            menu: menu
        });
    } catch (error) {
        console.error('Błąd wczytywania dashboardu:', error);
        res.status(500).send('Błąd serwera');
    }
});

module.exports = router;
