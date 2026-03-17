const mongoose = require('mongoose');

const tableSchema = new mongoose.Schema({
    restaurantId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    name: {
        type: String,
        required: [true, 'Nazwa stolika jest wymagana'],
        trim: true
    },
    link: {
        type: String,
        required: true
    }
}, { timestamps: true });

module.exports = mongoose.model('Table', tableSchema);
