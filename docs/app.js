/* === MyShikiPlayer landing — carousel + lightbox === */

(() => {
  'use strict';

  // --- Sticky nav scroll state ---

  const nav = document.querySelector('.nav');
  if (nav) {
    const onScroll = () => {
      nav.classList.toggle('is-scrolled', window.scrollY > 4);
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  // --- Carousel ---

  const carousel = document.querySelector('[data-carousel]');
  if (!carousel) return;

  const track = carousel.querySelector('[data-track]');
  const slides = Array.from(track.querySelectorAll('.carousel__slide'));
  const dotsContainer = carousel.querySelector('[data-dots]');
  const prevBtn = carousel.querySelector('[data-prev]');
  const nextBtn = carousel.querySelector('[data-next]');

  let activeIndex = 0;

  // Build dots
  slides.forEach((_, i) => {
    const dot = document.createElement('button');
    dot.className = 'carousel__dot';
    dot.type = 'button';
    dot.setAttribute('role', 'tab');
    dot.setAttribute('aria-label', `Скриншот ${i + 1}`);
    dot.setAttribute('aria-selected', i === 0 ? 'true' : 'false');
    dot.addEventListener('click', () => goTo(i));
    dotsContainer.appendChild(dot);
  });

  const dots = Array.from(dotsContainer.children);

  function goTo(index) {
    const clamped = Math.max(0, Math.min(slides.length - 1, index));
    const slide = slides[clamped];
    if (!slide) return;
    track.scrollTo({ left: slide.offsetLeft - track.offsetLeft, behavior: 'smooth' });
  }

  function setActive(index) {
    if (index === activeIndex) return;
    activeIndex = index;
    dots.forEach((d, i) => d.setAttribute('aria-selected', i === index ? 'true' : 'false'));
    prevBtn.disabled = index === 0;
    nextBtn.disabled = index === slides.length - 1;
  }

  // Detect active slide via IntersectionObserver
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
          const idx = slides.indexOf(entry.target);
          if (idx !== -1) setActive(idx);
        }
      });
    },
    { root: track, threshold: [0.6, 0.8] }
  );

  slides.forEach((s) => io.observe(s));

  prevBtn.addEventListener('click', () => goTo(activeIndex - 1));
  nextBtn.addEventListener('click', () => goTo(activeIndex + 1));

  // Keyboard nav when carousel/track has focus or hover
  track.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowLeft')  { e.preventDefault(); goTo(activeIndex - 1); }
    if (e.key === 'ArrowRight') { e.preventDefault(); goTo(activeIndex + 1); }
    if (e.key === 'Home')       { e.preventDefault(); goTo(0); }
    if (e.key === 'End')        { e.preventDefault(); goTo(slides.length - 1); }
  });

  // Initial state
  setActive(0);
  prevBtn.disabled = true;

  // --- Lightbox ---

  const lightbox = document.querySelector('[data-lightbox]');
  const lightboxImg = lightbox?.querySelector('[data-lightbox-img]');
  const lightboxClose = lightbox?.querySelector('[data-lightbox-close]');

  if (lightbox && lightboxImg) {
    slides.forEach((slide) => {
      const img = slide.querySelector('img');
      if (!img) return;
      img.addEventListener('click', () => {
        lightboxImg.src = img.src;
        lightboxImg.alt = img.alt || '';
        if (typeof lightbox.showModal === 'function') {
          lightbox.showModal();
        } else {
          lightbox.setAttribute('open', '');
        }
      });
    });

    lightboxClose?.addEventListener('click', () => lightbox.close());

    // Click on backdrop closes
    lightbox.addEventListener('click', (e) => {
      const rect = lightboxImg.getBoundingClientRect();
      const inside =
        e.clientX >= rect.left && e.clientX <= rect.right &&
        e.clientY >= rect.top && e.clientY <= rect.bottom;
      if (!inside && e.target !== lightboxClose) lightbox.close();
    });
  }

  // --- Latest release version (best-effort, fails silently) ---

  const versionEl = document.getElementById('version');
  const downloadBtn = document.getElementById('download-btn');

  if (versionEl) {
    fetch('https://api.github.com/repos/korenskoy/MyShikiPlayer/releases/latest', {
      headers: { 'Accept': 'application/vnd.github+json' },
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data) return;
        const tag = (data.tag_name || '').replace(/^v/, '');
        if (tag) versionEl.textContent = tag;
        const dmg = (data.assets || []).find((a) => a.name?.toLowerCase().endsWith('.dmg'));
        if (dmg && downloadBtn) {
          downloadBtn.href = dmg.browser_download_url;
        }
      })
      .catch(() => { /* offline / rate-limited — leave default */ });
  }
})();
