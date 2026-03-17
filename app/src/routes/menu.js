const express = require('express');
const router = express.Router();
const Menu = require('../models/Menu');
const User = require('../models/User'); // Dodane do wyszukiwania po nazwie restauracji
const { requireAuth } = require('../middleware/auth');
const upload = require('../config/upload');
const { toRestaurantSlug, restaurantSlugToRegex } = require('../utils/publicMenu');

// Initialize Menu document for a user if it doesn't exist yet
const ensureMenuExists = async (userId) => {
    let menu = await Menu.findOne({ restaurantId: userId });
    if (!menu) {
        menu = new Menu({ restaurantId: userId, categories: [] });
        await menu.save();
    }
    return menu;
};

// GET /menu (Dashboard View)
router.get('/', requireAuth, async (req, res) => {
    try {
        const menu = await ensureMenuExists(req.session.userId);
        res.render('menu', {
            title: 'Moje Menu | QResto',
            activePage: '/menu',
            menu: menu
        });
    } catch (error) {
        console.error('Błąd renderowania menu:', error);
        res.status(500).send('Wystąpił błąd serwera');
    }
});

// ADD CATEGORY
router.post('/category', requireAuth, async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) throw new Error('Nazwa kategorii jest wymagana');

        const menu = await ensureMenuExists(req.session.userId);

        // Push new category
        menu.categories.push({ name });
        await menu.save();

        res.redirect('/menu');
    } catch (error) {
        console.error('Błąd dodawania kategorii:', error);
        req.session.error = error.message;
        res.redirect('/menu');
    }
});

// REMOVE CATEGORY
router.post('/category/:categoryId/delete', requireAuth, async (req, res) => {
    try {
        const menu = await Menu.findOne({ restaurantId: req.session.userId });
        if (!menu) throw new Error('Menu nie znalezione');

        // Remove category from array
        menu.categories = menu.categories.filter(cat => cat._id.toString() !== req.params.categoryId);
        await menu.save();

        res.redirect('/menu');
    } catch (error) {
        console.error('Błąd usuwania kategorii:', error);
        req.session.error = 'Nie udało się usunąć kategorii';
        res.redirect('/menu');
    }
});

// ADD MENU ITEM (includes optional image upload)
router.post('/category/:categoryId/item', requireAuth, (req, res) => {
    upload.single('image')(req, res, async (err) => {
        if (err) {
            console.error('Błąd przesyłania zdjęcia:', err);
            req.session.error = err.message === 'File too large' ? 'Zdjęcie jest za duże (maks. 5MB)' : err.message;
            return res.redirect('/menu');
        }

        try {
            const { name, description, price, isAvailable } = req.body;
            const menu = await Menu.findOne({ restaurantId: req.session.userId });

            if (!menu) throw new Error('Menu nie znalezione');

            const category = menu.categories.id(req.params.categoryId);
            if (!category) throw new Error('Kategoria nie istnieje');

            const newItem = {
                name,
                description,
                price: Number(price),
                isAvailable: isAvailable === 'on' || isAvailable === true,
                image: req.file ? `/uploads/menu/${req.session.userId}/${req.file.filename}` : ''
            };

            category.items.push(newItem);
            await menu.save();

            res.redirect('/menu');
        } catch (error) {
            console.error('Błąd dodawania dania:', error);
            req.session.error = error.message;
            res.redirect('/menu');
        }
    });
});

// EDIT MENU ITEM
router.post('/item/:itemId/edit', requireAuth, (req, res) => {
    upload.single('image')(req, res, async (err) => {
        if (err) {
            console.error('Błąd przesyłania zdjęcia przy edycji:', err);
            req.session.error = err.message === 'File too large' ? 'Zdjęcie jest za duże (maks. 5MB)' : err.message;
            return res.redirect('/menu');
        }

        try {
            const { name, description, price, isAvailable, categoryId } = req.body;
            const menu = await Menu.findOne({ restaurantId: req.session.userId });
            if (!menu) throw new Error('Menu nie znalezione');

            let foundItem = null;

            // Szukamy dania we wszystkich kategoriach
            for (let cat of menu.categories) {
                const item = cat.items.id(req.params.itemId);
                if (item) {
                    // Zaktualizuj podstawowe pola
                    item.name = name;
                    item.description = description;
                    item.price = Number(price);
                    item.isAvailable = isAvailable === 'on' || isAvailable === true;

                    // Jeśli wgrano nowe zdjęcie
                    if (req.file) {
                        item.image = `/uploads/menu/${req.session.userId}/${req.file.filename}`;
                    }

                    foundItem = item;

                    // Zmiana kategorii dania (jeśli wymagana)
                    if (categoryId && cat._id.toString() !== categoryId) {
                        // Kopiujemy przedmiot 
                        const itemObj = item.toObject();

                        // Usuwamy ze starej kategorii
                        cat.items.pull(item._id);

                        // Szukamy nowej kategorii i dodajemy
                        const newCat = menu.categories.id(categoryId);
                        if (newCat) newCat.items.push(itemObj);
                    }
                    break;
                }
            }

            if (!foundItem) throw new Error('Nie znaleziono dania');

            await menu.save();
            res.redirect('/menu');
        } catch (error) {
            console.error('Błąd edycji dania:', error);
            req.session.error = error.message;
            res.redirect('/menu');
        }
    });
});

// DELETE MENU ITEM
router.post('/item/:itemId/delete', requireAuth, async (req, res) => {
    try {
        const menu = await Menu.findOne({ restaurantId: req.session.userId });
        if (!menu) throw new Error('Menu nie znalezione');

        for (let cat of menu.categories) {
            const item = cat.items.id(req.params.itemId);
            if (item) {
                // Mongoose pull syntax
                cat.items.pull(req.params.itemId);
                break;
            }
        }

        await menu.save();
        res.redirect('/menu');
    } catch (error) {
        console.error('Błąd usuwania dania:', error);
        req.session.error = 'Nie udało się usunąć dania';
        res.redirect('/menu');
    }
});

// GET /:restaurantSlug (PUBLIC MENU VIEW FOR CUSTOMERS)
// UWAGA: Musi być na samym dole, bo inaczej przejmie żądania takie jak /category czy /item
router.get('/:restaurantSlug', async (req, res) => {
    try {
        const { restaurantSlug } = req.params;
        const normalizedSlug = toRestaurantSlug(restaurantSlug);

        if (process.env.ROOT_DOMAIN && normalizedSlug) {
            const query = new URLSearchParams(req.query).toString();
            const protocol = (req.get('x-forwarded-proto') || req.protocol || 'https').split(',')[0].trim();
            const host = `${normalizedSlug}.${process.env.ROOT_DOMAIN}`;
            const suffix = query ? `/?${query}` : '/';
            return res.redirect(301, `${protocol}://${host}${suffix}`);
        }

        const user = await User.findOne({
            restaurantName: { $regex: restaurantSlugToRegex(normalizedSlug || restaurantSlug) }
        });

        if (!user) {
            return res.status(404).render('public-menu', {
                restaurantName: 'Nie znaleziono restauracji',
                menu: null
            });
        }

        const menu = await Menu.findOne({ restaurantId: user._id });

        res.render('public-menu', {
            restaurantName: user.restaurantName,
            menu: menu
        });
    } catch (error) {
        console.error('Błąd pobierania publicznego menu:', error);
        res.status(500).send('Wystąpił błąd podczas wczytywania menu.');
    }
});

module.exports = router;
