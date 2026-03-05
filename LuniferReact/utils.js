// Generates an array of random star objects for background animations
export function generateStars(count = 60) {
  return Array.from({ length: count }, (_, i) => ({
    id: i,
    top: `${Math.random() * 100}%`,
    left: `${Math.random() * 100}%`,
    size: Math.random() * 2 + 0.5,
    dur: `${Math.random() * 4 + 2}s`,
    delay: `${Math.random() * 5}s`,
  }));
}
