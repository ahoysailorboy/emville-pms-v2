const bookings = [
  {id:'EMV-0142',name:'Alex Morgan',in:'2026-11-14',out:'2026-11-16',rooms:2,guests:4,status:'confirmed',source:'Direct',amount:42000,paid:12000},
  {id:'EMV-0145',name:'Priya Nair',in:'2026-11-18',out:'2026-11-20',rooms:1,guests:2,status:'confirmed',source:'Booking.com',amount:18000,paid:18000},
  {id:'EMV-0148',name:'Daniel Reed',in:'2026-11-21',out:'2026-11-23',rooms:2,guests:4,status:'confirmed',source:'Airbnb',amount:36000,paid:18000},
  {id:'EMV-0151',name:'Maya Iyer',in:'2026-11-25',out:'2026-11-27',rooms:1,guests:2,status:'confirmed',source:'Direct',amount:18000,paid:9000},
  {id:'EMV-0154',name:'Ethan Cole',in:'2026-11-28',out:'2026-11-30',rooms:2,guests:3,status:'confirmed',source:'Direct',amount:32000,paid:12000},
  {id:'EMV-0158',name:'Sofia Ali',in:'2026-12-01',out:'2026-12-03',rooms:1,guests:2,status:'confirmed',source:'Booking.com',amount:18000,paid:0},
  {id:'EMV-0146',name:'Maria Costa',in:'2026-11-19',out:'2026-11-22',rooms:1,guests:2,status:'enquiry',source:'Direct',amount:24000,paid:0},
  {id:'EMV-0149',name:'Arjun Menon',in:'2026-11-21',out:'2026-11-23',rooms:1,guests:2,status:'enquiry',source:'Direct',amount:18000,paid:0},
  {id:'EMV-0137',name:'Rohan Mehta',in:'2026-11-10',out:'2026-11-12',rooms:2,guests:4,status:'completed',source:'Direct',amount:36000,paid:36000},
  {id:'EMV-0130',name:'Emily Watson',in:'2026-11-06',out:'2026-11-09',rooms:1,guests:2,status:'completed',source:'Airbnb',amount:27000,paid:27000},
];
const icon = name => `<svg aria-hidden="true"><use href="#icon-${name}"/></svg>`;
const date = value => new Date(value+'T12:00:00');
const short = value => date(value).toLocaleDateString('en-GB',{day:'numeric',month:'short'});
const money = value => new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(value);
const dialog = document.querySelector('#dialog'), panel = document.querySelector('#dialog-content');
let tab = 'upcoming', from = '', to = '', source = 'all';
function render() {
  const query = document.querySelector('#search').value.toLowerCase().trim();
  const rows = bookings.filter(b => (tab==='upcoming'?b.status==='confirmed':tab==='past'?b.status==='completed':b.status==='enquiry') && `${b.name} ${b.id} ${b.source}`.toLowerCase().includes(query) && (!from || b.in>=from) && (!to || b.in<=to) && (source==='all'||b.source===source));
  document.querySelector('#list-title').textContent = tab==='upcoming'?'Upcoming stays':tab==='past'?'Past stays':'Booking enquiries';
  document.querySelector('#list-count').textContent = (tab==='upcoming'?'Next 30 days':tab==='past'?'Last 30 days':'Awaiting confirmation')+' · '+rows.length;
  const list = document.querySelector('#booking-list');
  list.setAttribute('aria-labelledby','tab-'+tab);
  list.innerHTML = rows.length ? rows.map(b => {
    const arrival = b.in==='2026-11-14';
    const status = b.status==='enquiry'?'Enquiry':b.status==='completed'?'Completed':arrival?'Arrival today':'Confirmed';
    return `<button class="booking" data-booking="${b.id}" aria-label="View booking for ${b.name}"><span class="date-badge"><b>${date(b.in).getDate()}</b><span>${date(b.in).toLocaleDateString('en-GB',{month:'short'}).toUpperCase()}</span></span><span class="booking-info"><span class="guest-line"><b>${b.name}</b>${icon('chevron')}</span><p>${short(b.in)}–${short(b.out)} · ${b.rooms} ${b.rooms===1?'room':'rooms'} · ${b.guests} guests</p><span class="booking-bottom"><span class="tag ${b.status==='enquiry'?'amber':arrival?'arrival':''}">${status}</span><span class="source">${b.source}</span></span></span></button>`;
  }).join('') : '<div class="empty">No bookings match your search.<br>Try another guest, reference or date range.</div>';
  list.querySelectorAll('[data-booking]').forEach(button => button.onclick = () => detail(bookings.find(b => b.id===button.dataset.booking)));
  document.querySelector('.filter-button').setAttribute('aria-pressed',String(Boolean(from||to||source!=='all')));
}
function show(html) { panel.innerHTML=html; dialog.showModal(); }
function detail(b) {
  show(`<div class="eyebrow">BOOKING / ${b.id}</div><h2 style="margin-top:12px">${b.name}</h2><span class="tag ${b.status==='enquiry'?'amber':''}">${b.status==='enquiry'?'Enquiry':b.status==='completed'?'Completed':'Confirmed'}</span><div class="detail-grid"><div><span>Check-in</span><b>${short(b.in)} 2026</b></div><div><span>Check-out</span><b>${short(b.out)} 2026</b></div><div><span>Rooms & guests</span><b>${b.rooms} ${b.rooms===1?'room':'rooms'} · ${b.guests} guests</b></div><div><span>Booking source</span><b>${b.source}</b></div><div><span>Total amount</span><b>${money(b.amount)}</b></div><div><span>Balance due</span><b>${money(b.amount-b.paid)}</b></div></div><p>Guest details, payments and receipts stay together in the full booking.</p><button class="primary" id="view-full">View full booking ${icon('chevron')}</button>`);
  document.querySelector('#view-full').onclick=()=>{dialog.close();notify('Full booking selected · design preview');};
}
function selectTab(next) {
  tab=next;
  document.querySelectorAll('[data-tab]').forEach(b=>{const active=b.dataset.tab===tab;b.setAttribute('aria-selected',String(active));b.tabIndex=active?0:-1;});
  render();
}
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>selectTab(b.dataset.tab));
document.querySelector('.tabs').onkeydown = e => {if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();const tabs=['upcoming','past','enquiries'];let i=tabs.indexOf(tab);i=e.key==='Home'?0:e.key==='End'?2:(i+(e.key==='ArrowRight'?1:2))%3;selectTab(tabs[i]);document.querySelector('#tab-'+tab).focus();};
document.querySelector('#search').oninput=render;
document.querySelector('.filter-button').onclick=()=>{
  show(`<div class="eyebrow">FIND THE RIGHT STAY</div><h2 style="margin-top:12px">Advanced search</h2><p>Narrow your list by check-in date and booking source.</p><form id="filters"><label for="from">Check-in from</label><input id="from" type="date" value="${from}"><label for="to">Check-in to</label><input id="to" type="date" value="${to}"><label for="source">Booking source</label><select id="source"><option value="all">All sources</option><option>Direct</option><option>Booking.com</option><option>Airbnb</option></select><div class="dialog-actions"><button class="secondary" id="reset" type="button">Reset</button><button class="primary" type="submit">Apply filters</button></div></form>`);
  document.querySelector('#source').value=source;
  for(const id of ['from','to']) document.querySelector('#'+id).oninput=()=>document.querySelector('#to').setCustomValidity('');
  document.querySelector('#filters').onsubmit=e=>{e.preventDefault();const first=document.querySelector('#from'),last=document.querySelector('#to');last.setCustomValidity(first.value&&last.value&&last.value<first.value?'Choose an end date on or after the start date.':'');if(!e.target.reportValidity())return;from=first.value;to=last.value;source=document.querySelector('#source').value;dialog.close();render();};
  document.querySelector('#reset').onclick=()=>{from='';to='';source='all';dialog.close();render();};
};
document.querySelector('.close').onclick=()=>dialog.close();
let timer;function notify(message){const t=document.querySelector('.toast');t.textContent=message;t.hidden=false;clearTimeout(timer);timer=setTimeout(()=>t.hidden=true,2600);}
document.querySelector('#new-booking').onclick=()=>notify('New booking selected · design preview');
document.querySelectorAll('[data-nav]').forEach(b=>b.onclick=()=>{if(b.dataset.nav==='Bookings'){selectTab('upcoming');document.querySelector('#search').value='';render();}else notify(b.dataset.nav+' selected · design preview');});
const drawer=document.querySelector('.drawer');function closeMenu(){drawer.classList.remove('open');drawer.setAttribute('aria-hidden','true');document.querySelector('.menu-button').focus();}
document.querySelector('.menu-button').onclick=()=>{drawer.classList.add('open');drawer.setAttribute('aria-hidden','false');document.querySelector('.drawer-close').focus();};
document.querySelector('.drawer-close').onclick=closeMenu;drawer.onclick=e=>{if(e.target===drawer)closeMenu();};
document.querySelectorAll('[data-menu]').forEach(b=>b.onclick=()=>{closeMenu();notify(b.dataset.menu+' selected · design preview');});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&drawer.classList.contains('open'))closeMenu();});
render();
