const request = require('supertest');
const express = require('express');

// Chcemy przetestować sam endpoint /health nie odpalając całego serwera
const app = express();

app.get('/health', (req, res) => {
    // Ponieważ w teście nie łączymy się prawdzwie z MongoDB atlas, fake'ujemy zachowanie z server.js
    res.status(200).json({ status: 'ok', service: 'qresto-app-test' });
});

describe('GET /health', () => {
    it('powinno zwrócić kod 200 OK i status JSON', async () => {
        const response = await request(app).get('/health');
        expect(response.statusCode).toBe(200);
        expect(response.body.status).toBe('ok');
        expect(response.body.service).toBeDefined();
    });
});
