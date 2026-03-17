const DEFAULT_RESERVED_SUBDOMAINS = new Set(['www', 'zabbix']);

const toRestaurantSlug = (name = '') => {
    return name
        .normalize('NFKD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .replace(/-{2,}/g, '-');
};

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const restaurantSlugToRegex = (slug = '') => {
    const escaped = escapeRegExp(slug.toLowerCase());
    const flexible = escaped.replace(/-/g, '[\\s\\-]+');
    return new RegExp(`^${flexible}$`, 'i');
};

const getRequestHost = (req) => {
    const rawHost = (req.get('x-forwarded-host') || req.get('host') || '').split(',')[0].trim().toLowerCase();
    return rawHost.replace(/:\d+$/, '');
};

const getRestaurantSubdomain = (req) => {
    const host = getRequestHost(req);
    const rootDomain = (process.env.ROOT_DOMAIN || '').trim().toLowerCase();

    if (!host || !rootDomain) {
        return null;
    }

    if (host === rootDomain) {
        return null;
    }

    if (!host.endsWith(`.${rootDomain}`)) {
        return null;
    }

    const subdomain = host.slice(0, -(rootDomain.length + 1));

    if (!subdomain || subdomain.includes('.')) {
        return null;
    }

    if (DEFAULT_RESERVED_SUBDOMAINS.has(subdomain)) {
        return null;
    }

    return subdomain;
};

module.exports = {
    toRestaurantSlug,
    restaurantSlugToRegex,
    getRestaurantSubdomain
};
