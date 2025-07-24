
// Untuk kebutuhan tambahan kalau mau dinamis
document.addEventListener('DOMContentLoaded', function () {
  console.log('Dashboard loaded!');
});

// Fungsi update tanggal dan waktu di header
function updateDateTime() {
  const now = new Date();
  const options = {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  };
  const formattedDateTime = now.toLocaleDateString('id-ID', options);
  document.getElementById('currentDateTime').innerText = formattedDateTime;
}
updateDateTime();
setInterval(updateDateTime, 1000); // Update tiap detik

// Fungsi untuk cari data keluar (tampilkan modal)
function cariDataKeluar() {
  const rfid = document.getElementById('rfidInput').value;
  if (!rfid) return alert('Masukkan UID terlebih dahulu.');

  fetch(`/get_info?rfid=${rfid}`)
    .then(res => res.json())
    .then(data => {
      if (data.error) return alert(data.error);
      document.getElementById('infoSlot').textContent = data.slot;
      document.getElementById('infoMasuk').textContent = data.waktu_masuk;
      document.getElementById('infoKeluar').textContent = data.waktu_keluar;
      document.getElementById('infoTarif').textContent = data.tarif;
      document.getElementById('hiddenId').value = rfid;
      document.getElementById('infoModal').style.display = 'block';
    })
    .catch(err => alert('Gagal memuat data keluar.'));
}

// Submit konfirmasi keluar
document.getElementById('hapusForm').addEventListener('submit', function (e) {
  e.preventDefault();
  const rfid = document.getElementById('hiddenId').value;

  fetch('/confirm_exit', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ id: rfid })
  })
    .then(res => {
      if (res.ok) {
        alert('Data berhasil diperbarui (waktu keluar dicatat).');
        document.getElementById('infoModal').style.display = 'none';
        window.location.reload(); // Reload data di tabel
      } else {
        alert('Gagal menghapus data.');
      }
    })
    .catch(err => {
      console.error(err);
      alert('Terjadi kesalahan saat menghapus data.');
    });
});

// Deteksi UID baru dari RFID keluar (anti-spam)
let lastProcessedUID = '';
let lastProcessedTime = 0;
const cooldown = 5000; // dalam ms

function checkForExitRFID() {
  fetch('/check_latest_uid')
    .then(res => res.json())
    .then(data => {
      const now = Date.now();

      if (data.rfid && (data.rfid !== lastProcessedUID || (now - lastProcessedTime > cooldown))) {
        lastProcessedUID = data.rfid;
        lastProcessedTime = now;

        document.getElementById('rfidInput').value = data.rfid;
        cariDataKeluar(); // tampilkan modal info
      }
    })
    .catch(err => {
      console.error('Error checking UID:', err);
    });
}

setInterval(checkForExitRFID, 2000); // Cek UID setiap 2 detik

let lastUID = null;

function checkForEntryRFID() {
  fetch('/check_entry_uid')
    .then(res => res.json())
    .then(data => {
      if (data.rfid && data.rfid !== lastUID) {
        lastUID = data.rfid;
        // Reload otomatis agar data baru tampil
        location.reload();
      }
    })
    .catch(err => console.error('RFID check error:', err));
}

setInterval(checkForEntryRFID, 2000); // cek setiap 2 detik


let currentSlot = 1;

function isiSlot() {
  if (currentSlot > 12) {
    alert("Semua slot sudah terisi.");
    return;
  }

  const slot = document.getElementById(`slot${currentSlot}`);
  if (slot && !slot.classList.contains('filled')) {
    slot.classList.add('filled');
    currentSlot++;
  }
}

// Fungsi untuk cari data keluar dan tampilkan modal konfirmasi
function cariDataKeluar() {
  const rfid = document.getElementById('rfidInput').value;
  if (!rfid) return alert('Masukkan UID terlebih dahulu.');

  fetch(`/get_info?rfid=${rfid}`)
    .then(res => res.json())
    .then(data => {
      if (data.error) return alert(data.error);
      document.getElementById('infoSlot').textContent = data.slot;
      document.getElementById('infoMasuk').textContent = data.waktu_masuk;
      document.getElementById('infoKeluar').textContent = data.waktu_keluar;
      document.getElementById('infoTarif').textContent = data.tarif;
      document.getElementById('hiddenId').value = rfid;

      // Tampilkan modal konfirmasi keluar
      document.getElementById('infoModal').style.display = 'block';
    })
    .catch(err => alert('Gagal memuat data keluar.'));
}

setInterval(() => {
  fetch('/status_bantuan')
    .then(res => res.json())
    .then(data => {
      const notif = document.getElementById('notifBantuan');
      if (data.bantuan) notif.classList.remove('d-none');
      else notif.classList.add('d-none');
    });
}, 3000);

fetch("/konfirmasi_keluar", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ uid: uid })
})


document.getElementById('btnInputMasuk').addEventListener('click', function (e) {
  e.preventDefault();
  fetch('/input_masuk', { method: 'POST' })
    .then(response => response.json())
    .then(data => {
      alert(data.message);  // Optional: kasih notifikasi
    });
});