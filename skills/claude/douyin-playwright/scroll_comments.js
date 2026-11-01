
(async () => {
  const cl = document.querySelector('[data-e2e=comment-list]');
  if (!cl) return 'no comment list';
  for (let i = 0; i < 10; i++) {
    cl.scrollTop = cl.scrollHeight;
    await new Promise(r => setTimeout(r, 1000));
  }
  return document.querySelectorAll('[data-e2e=comment-item]').length;
})()
