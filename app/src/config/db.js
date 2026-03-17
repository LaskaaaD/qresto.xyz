const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        const uri = process.env.MONGODB_URI;
        if (!uri) {
            throw new Error('MONGODB_URI variable is not defined in .env');
        }

        await mongoose.connect(uri);

        console.log('MongoDB połączone pomyślnie');
    } catch (error) {
        console.error('Błąd połączenia z bazą MongoDB:', error.message);
        process.exit(1);
    }
};

module.exports = connectDB;
