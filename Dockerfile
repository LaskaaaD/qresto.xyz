# Używamy lekkiego obrazu bazowego Alpine w wersji Node 20
FROM node:20-alpine

# Ustawienie katalogu roboczego w kontenerze
WORKDIR /usr/src/app

# Kopiowanie plików definicji pakietów z katalogu aplikacji
# Gwiazdka (*) sprawia, że kopiujemy zarówno package.json jak i package-lock.json (jeśli istnieje)
COPY app/package*.json ./

# Instalacja tylko niezbędnych paczek produkcyjnych
RUN npm install --production

# Skopiowanie całej warstwy logiki z katalogu \`app\` z pominięciem node_modules dzięki .dockerignore
COPY app/ .

# Aplikacja działa na porcie 3000
EXPOSE 3000

# Komenda uruchomieniowa (plikiem wejściowym jest server.js)
CMD ["node", "server.js"]
