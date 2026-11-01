const items = [...document.querySelectorAll('[data-e2e=comment-item]')];
const texts = items.map(el => {
  const raw = el.innerText;
  const lines = raw.split('\n');
  const filtered = lines.filter(l => {
    const t = l.trim();
    return t.length > 5 && !/^\d+$/.test(t) && !t.includes('展开') && !/\d+(天|周|月|年|小时|分钟)前/.test(t);
  });
  const unique = [...new Set(filtered.map(l => l.trim()))];
  return unique.join(' | ');
});
JSON.stringify(texts);
