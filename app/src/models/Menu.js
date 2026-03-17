const mongoose = require('mongoose');

// Schemat pojedynczego dania
const menuItemSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Nazwa dania jest wymagana'],
        trim: true
    },
    description: {
        type: String,
        trim: true
    },
    price: {
        type: Number,
        required: [true, 'Cena jest wymagana'],
        min: [0, 'Cena nie może być ujemna']
    },
    image: {
        type: String,
        default: '' // Ścieżka do zdjęcia (lokalnie przez multer)
    },
    isAvailable: {
        type: Boolean,
        default: true
    }
}, { timestamps: true });

// Schemat kategorii, zawierający tablicę dań
const categorySchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Nazwa kategorii jest wymagana'],
        trim: true
    },
    items: [menuItemSchema] // Embedded documents - Dania
}, { timestamps: true });

// Główny schemat Menu restauracji
const menuSchema = new mongoose.Schema({
    restaurantId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        unique: true // Każda restauracja ma dokładnie jedno Menu
    },
    categories: [categorySchema] // Embedded documents - Kategorie
}, { timestamps: true });

const Menu = mongoose.model('Menu', menuSchema);
module.exports = Menu;
