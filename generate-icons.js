const { createCanvas } = require('canvas');
const fs = require('fs');
const path = require('path');

const sizes = [72, 96, 128, 144, 152, 192, 384, 512];
const outDir = path.join(__dirname, 'web', 'assets');

if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

sizes.forEach(size => {
  const c = createCanvas(size, size);
  const ctx = c.getContext('2d');
  
  const g = ctx.createLinearGradient(0, 0, size, size);
  g.addColorStop(0, '#e05a00');
  g.addColorStop(1, '#ff8c00');
  ctx.fillStyle = g;
  
  const r = size * 0.18;
  ctx.beginPath();
  ctx.moveTo(r, 0);
  ctx.lineTo(size - r, 0);
  ctx.quadraticCurveTo(size, 0, size, r);
  ctx.lineTo(size, size - r);
  ctx.quadraticCurveTo(size, size, size - r, size);
  ctx.lineTo(r, size);
  ctx.quadraticCurveTo(0, size, 0, size - r);
  ctx.lineTo(0, r);
  ctx.quadraticCurveTo(0, 0, r, 0);
  ctx.fill();
  
  ctx.fillStyle = '#fff';
  ctx.font = `bold ${Math.round(size * 0.5)}px Arial, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('E', size / 2, size / 2);
  
  const buf = c.toBuffer('image/png');
  const filePath = path.join(outDir, `icon-${size}.png`);
  fs.writeFileSync(filePath, buf);
  console.log(`Created: ${filePath} (${buf.length} bytes)`);
});

console.log('All icons generated!');
