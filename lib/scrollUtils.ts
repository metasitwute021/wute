export const getScrollProgress = () => {
  if (typeof window === 'undefined') return 0;
  const scrollTop = window.scrollY;
  const docHeight =
    document.documentElement.scrollHeight - window.innerHeight;
  return docHeight > 0 ? scrollTop / docHeight : 0;
};

export const getScrollSection = () => {
  if (typeof window === 'undefined') return 0;
  const scrollTop = window.scrollY;
  const docHeight =
    document.documentElement.scrollHeight - window.innerHeight;
  const progress = docHeight > 0 ? scrollTop / docHeight : 0;

  // 8 sections
  return Math.floor(progress * 8);
};

export const easeInOutCubic = (t: number) => {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
};

export const easeOutQuad = (t: number) => {
  return 1 - (1 - t) * (1 - t);
};

export const easeInQuad = (t: number) => {
  return t * t;
};
