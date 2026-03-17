require('dotenv').config();
const express = require('express');
const path = require('path');
const session = require('express-session');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const csrf = require('csurf');
const mongoose = require('mongoose');
const os = require('os');
const connectDB = require('./src/config/db');
const MongoStore = require('connect-mongo').default;
const { setLocals } = require('./src/middleware/auth');

const indexRouter = require('./src/routes/index');
const authRouter = require('./src/routes/auth');
const menuRouter = require('./src/routes/menu');
const qrRouter = require('./src/routes/qr');

const app = express();
const PORT = process.env.PORT || 3000;
const isProduction = process.env.NODE_ENV === 'production';

if (!process.env.MONGODB_URI) {
    throw new Error('MONGODB_URI variable is not defined in .env');
}

if (!process.env.SESSION_SECRET) {
    throw new Error('SESSION_SECRET variable is not defined in .env');
}

// Connect Database
connectDB();

// View engine setup
app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'ejs');
app.set('trust proxy', 1);

// Middleware
app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: false
}));
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 50,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Zbyt wiele prób. Spróbuj ponownie za kilka minut.'
});

// Session Configuration
app.use(session({
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    store: MongoStore.create({ mongoUrl: process.env.MONGODB_URI }),
    proxy: true,
    name: 'qresto.sid',
    cookie: {
        maxAge: 1000 * 60 * 60 * 24, // 1 day
        httpOnly: true,
        sameSite: 'lax',
        secure: isProduction
    }
}));

app.use('/auth', authLimiter);

const csrfProtection = csrf();
app.use(csrfProtection);
app.use((req, res, next) => {
    res.locals.csrfToken = req.csrfToken();
    next();
});

// Set Global EJS Locals (user, error)
app.use(setLocals);

// Routes
app.use('/', indexRouter);
app.use('/auth', authRouter);
app.use('/menu', menuRouter);
app.use('/qr', qrRouter);

const getDbStatusMap = () => ({
    0: 'disconnected',
    1: 'connected',
    2: 'connecting',
    3: 'disconnecting',
    99: 'uninitialized'
});

const buildHealthPayload = () => {
    const dbState = mongoose.connection.readyState;
    const dbStatusMap = getDbStatusMap();

    return {
        status: dbState === 1 ? 'ok' : 'error',
        timestamp: new Date().toISOString(),
        service: 'qresto-app',
        instance: process.env.HOSTNAME || os.hostname(),
        uptime: process.uptime(),
        memory: {
            rss: process.memoryUsage().rss,
            heapTotal: process.memoryUsage().heapTotal,
            heapUsed: process.memoryUsage().heapUsed,
            external: process.memoryUsage().external
        },
        database: {
            stateCode: dbState,
            status: dbStatusMap[dbState] || 'unknown'
        }
    };
};

// Liveness probe: process is running
app.get('/live', (req, res) => {
    res.status(200).json({
        status: 'alive',
        timestamp: new Date().toISOString(),
        service: 'qresto-app',
        instance: process.env.HOSTNAME || os.hostname()
    });
});

// Readiness probe: app is ready to serve traffic only when DB is connected
app.get('/ready', (req, res) => {
    const dbState = mongoose.connection.readyState;
    const payload = buildHealthPayload();

    if (dbState === 1) {
        return res.status(200).json(payload);
    }

    return res.status(503).json(payload);
});

// Health check endpoint for Zabbix/DevOps
app.get('/health', (req, res) => {
    const dbState = mongoose.connection.readyState;
    const payload = buildHealthPayload();

    if (dbState === 1) {
        return res.status(200).json(payload);
    }

    return res.status(503).json(payload);
});

app.use((err, req, res, next) => {
    if (err && err.code === 'EBADCSRFTOKEN') {
        req.session.error = 'Sesja formularza wygasła. Odśwież stronę i spróbuj ponownie.';
        const referer = req.get('referer');
        let fallbackPath = req.session && req.session.userId ? '/menu' : '/auth/login';

        if (req.session && req.session.userId) {
            if (req.path.startsWith('/qr')) {
                fallbackPath = '/qr';
            } else if (req.path.startsWith('/menu')) {
                fallbackPath = '/menu';
            }
        }

        return res.redirect(referer || fallbackPath);
    }

    return next(err);
});

// Start server
app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
