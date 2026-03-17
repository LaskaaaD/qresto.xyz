const express = require('express');
const router = express.Router();
const User = require('../models/User');
const { forwardAuthenticated } = require('../middleware/auth');

// GET /register
router.get('/register', forwardAuthenticated, (req, res) => {
    res.render('register', { title: 'Rejestracja - QResto' });
});

// POST /register
router.post('/register', forwardAuthenticated, async (req, res) => {
    try {
        const { restaurantName, email, password } = req.body;

        // Sprawdź, czy użytkownik już istnieje
        const existingUser = await User.findOne({ email: email.toLowerCase() });
        if (existingUser) {
            req.session.error = 'Konto z tym adresem e-mail już istnieje.';
            return res.redirect('/auth/register');
        }

        // Nowy użytkownik
        const newUser = new User({
            restaurantName,
            email,
            password
        });

        await newUser.save();

        // Automatyczne logowanie po rejestracji
        req.session.userId = newUser._id;
        req.session.user = {
            id: newUser._id,
            restaurantName: newUser.restaurantName,
            email: newUser.email
        };

        res.redirect('/dashboard');
    } catch (error) {
        console.error('Błąd podczas rejestracji:', error);

        if (error.name === 'ValidationError') {
            const messages = Object.values(error.errors).map(val => val.message);
            req.session.error = messages.join('. ');
        } else {
            req.session.error = 'Wystąpił błąd serwera. Spróbuj ponownie.';
        }

        res.redirect('/auth/register');
    }
});

// GET /login
router.get('/login', forwardAuthenticated, (req, res) => {
    res.render('login', { title: 'Logowanie - QResto' });
});

// POST /login
router.post('/login', forwardAuthenticated, async (req, res) => {
    try {
        const { email, password } = req.body;

        // Szukaj użytkownika
        const user = await User.findOne({ email: email.toLowerCase() });
        if (!user) {
            req.session.error = 'Nieprawidłowy e-mail lub hasło.';
            return res.redirect('/auth/login');
        }

        // Sprawdź hasło
        const isMatch = await user.matchPassword(password);
        if (!isMatch) {
            req.session.error = 'Nieprawidłowy e-mail lub hasło.';
            return res.redirect('/auth/login');
        }

        // Pomyślne logowanie
        req.session.userId = user._id;
        req.session.user = {
            id: user._id,
            restaurantName: user.restaurantName,
            email: user.email
        };

        res.redirect('/dashboard');
    } catch (error) {
        console.error('Błąd logowania:', error);
        req.session.error = 'Wystąpił błąd serwera. Spróbuj ponownie.';
        res.redirect('/auth/login');
    }
});

// GET /logout
router.get('/logout', (req, res) => {
    req.session.destroy((err) => {
        if (err) {
            console.error('Błąd przy niszczeniu sesji:', err);
        }
        res.redirect('/');
    });
});

module.exports = router;
