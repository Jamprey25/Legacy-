// Geohash encoding. Precision 9 (~4.8m) for drop points; precision 5 (~4.9km)
// for coarse zone queries. Pure function — no DB dependency, easy to test.
//
// Implementation: base32 encoding of interleaved lat/lng bits (standard Niemeyer geohash).

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

export function encode(lat: number, lng: number, precision = 9): string {
  let minLat = -90, maxLat = 90;
  let minLng = -180, maxLng = 180;
  let hash = "";
  let bits = 0;
  let bitsTotal = 0;
  let hashValue = 0;
  let isEven = true;

  while (hash.length < precision) {
    if (isEven) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) {
        hashValue = (hashValue << 1) | 1;
        minLng = mid;
      } else {
        hashValue = hashValue << 1;
        maxLng = mid;
      }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) {
        hashValue = (hashValue << 1) | 1;
        minLat = mid;
      } else {
        hashValue = hashValue << 1;
        maxLat = mid;
      }
    }
    isEven = !isEven;

    if (++bits === 5) {
      hash += BASE32[hashValue];
      bits = 0;
      bitsTotal += 5;
      hashValue = 0;
    }
  }

  return hash;
}

/** Return the 8 neighbours of a geohash cell (used for scan queries). */
export function neighbours(hash: string): string[] {
  const decoded = decode(hash);
  const { lat, lng, latErr, lngErr } = decoded;
  const offsets: [number, number][] = [
    [latErr * 2, 0], [-latErr * 2, 0], [0, lngErr * 2], [0, -lngErr * 2],
    [latErr * 2, lngErr * 2], [latErr * 2, -lngErr * 2],
    [-latErr * 2, lngErr * 2], [-latErr * 2, -lngErr * 2],
  ];
  return offsets.map(([dlat, dlng]) =>
    encode(
      Math.max(-90, Math.min(90, lat + dlat)),
      ((lng + dlng + 180) % 360) - 180,
      hash.length,
    ),
  );
}

interface DecodedGeohash {
  lat: number;
  lng: number;
  latErr: number;
  lngErr: number;
}

function decode(hash: string): DecodedGeohash {
  let minLat = -90, maxLat = 90;
  let minLng = -180, maxLng = 180;
  let isEven = true;

  for (const char of hash) {
    const bits = BASE32.indexOf(char);
    for (let bit = 4; bit >= 0; bit--) {
      const bitN = (bits >> bit) & 1;
      if (isEven) {
        const mid = (minLng + maxLng) / 2;
        if (bitN) minLng = mid; else maxLng = mid;
      } else {
        const mid = (minLat + maxLat) / 2;
        if (bitN) minLat = mid; else maxLat = mid;
      }
      isEven = !isEven;
    }
  }

  return {
    lat: (minLat + maxLat) / 2,
    lng: (minLng + maxLng) / 2,
    latErr: (maxLat - minLat) / 2,
    lngErr: (maxLng - minLng) / 2,
  };
}

/** Haversine distance in metres between two WGS-84 points. */
export function distanceMetres(
  lat1: number, lng1: number,
  lat2: number, lng2: number,
): number {
  const R = 6_371_000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg: number) {
  return (deg * Math.PI) / 180;
}
