const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
    restaurantName: {
        type: String,
        required: [true, 'Nazwa restauracji jest wymagana'],
        trim: true
    },
    email: {
        type: String,
        required: [true, 'Adres e-mail jest wymagany'],
        unique: true,
        lowercase: true,
        trim: true,
        match: [/^\S+@\S+\.\S+$/, 'Proszę podać prawidłowy adres e-mail']
    },
    password: {
        type: String,
        required: [true, 'Hasło jest wymagane'],
        minlength: [6, 'Hasło musi mieć co najmniej 6 znaków']
    },
    logo: {
        type: String,
        default: '' // Ścieżka do opcjonalnego logotypu restauracji w kodach QR
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

// Middleware przed zapisem do bazy dodający bezpieczne hashowanie hasła
userSchema.pre('save', async function () {
    // Hashujemy tylko jeśli hasło zostało zmienione / jest nowe
    if (!this.isModified('password')) {
        return;
    }

    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
});

// Metoda do sprawdzania logowania
userSchema.methods.matchPassword = async function (enteredPassword) {
    return await bcrypt.compare(enteredPassword, this.password);
};

const User = mongoose.model('User', userSchema);
module.exports = User;
