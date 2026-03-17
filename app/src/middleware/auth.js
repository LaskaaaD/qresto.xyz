const requireAuth = (req, res, next) => {
    if (req.session && req.session.userId) {
        return next();
    }
    // Gdy niezalogowany
    res.redirect('/login');
};

const forwardAuthenticated = (req, res, next) => {
    if (req.session && req.session.userId) {
        return res.redirect('/dashboard');
    }
    next();
};

const setLocals = (req, res, next) => {
    res.locals.user = req.session.user || null;
    res.locals.error = req.session.error || null;
    // Czyścimy błąd po jednorazowym przekazaniu na widok
    delete req.session.error;
    next();
};

module.exports = {
    requireAuth,
    forwardAuthenticated,
    setLocals
};
