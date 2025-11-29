// Avatar UI: listen to conversation start/end and animate avatar + header
(function(){
  function safe(q){ try { return document.querySelector(q); } catch { return null; } }
  const avatar = safe('#a11-avatar') as HTMLImageElement | null;
  const header = safe('.nossen-flame') as HTMLElement | null;
  if (!avatar && !header) return;

  const staticSrc = avatar ? avatar.getAttribute('src') || '' : '';
  const animSrc = avatar ? (avatar.getAttribute('data-anim') || '') : '';

  function onStart(){
    try {
      if (header) header.classList.add('speaking');
      if (avatar && animSrc) {
        avatar.dataset._static = staticSrc;
        avatar.src = animSrc;
      }
    } catch (e) {}
  }
  function onEnd(){
    try {
      if (header) header.classList.remove('speaking');
      if (avatar) {
        const s = avatar.dataset._static || staticSrc;
        if (s) avatar.src = s;
      }
    } catch (e) {}
  }

  window.addEventListener('conversation:start', onStart);
  window.addEventListener('conversation:end', onEnd);

  // Also expose small API for manual control
  (globalThis as any).A11AvatarUI = { start: onStart, end: onEnd };
})();
