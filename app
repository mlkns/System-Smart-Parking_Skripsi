from flask import Flask, render_template, request, redirect, url_for, jsonify, session, flash
from flask_mysqldb import MySQL
from datetime import datetime
import time

app = Flask(__name__)

bantuan_aktif = False
servo_masuk_status = False
app.secret_key = 'rahasia-admin-login'

USERNAME_ADMIN = 'admin'
PASSWORD_ADMIN = '12345'

# Konfigurasi database
app.config['MYSQL_HOST'] = 'localhost'
app.config['MYSQL_USER'] = 'root'
app.config['MYSQL_PASSWORD'] = ''
app.config['MYSQL_DB'] = 'dashboard'

mysql = MySQL(app)

latest_uid = None
last_uid_time = 0
latest_uid_entry = None
last_confirmed_exit_uid = None 

# --- Helper function untuk slot A1-A6 dan B1-B6 ---
SLOT_SQL = """
    SELECT slot FROM (
        SELECT CONCAT('A', n) AS slot FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) nums
        UNION ALL
        SELECT CONCAT('B', n) FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) nums
    ) all_slots
    WHERE slot NOT IN (SELECT slot FROM parkir_db WHERE waktu_keluar IS NULL)
    ORDER BY slot ASC
    LIMIT 1
"""

@app.route('/admin', methods=['GET', 'POST'])
def index():
    if not session.get('admin_logged_in'):
        return redirect(url_for('login'))

    if request.method == 'POST':
        rfid = request.form['rfid']
        waktu_masuk = datetime.now()
        cur = mysql.connection.cursor()

        cur.execute(SLOT_SQL)
        available_slot = cur.fetchone()

        if available_slot:
            new_slot = available_slot[0]
            cur.execute("INSERT INTO parkir_db (rfid, waktu_masuk, slot) VALUES (%s, %s, %s)",
                        (rfid, waktu_masuk, new_slot))
            mysql.connection.commit()

        cur.close()
        return redirect(url_for('index'))

    cur = mysql.connection.cursor()
    cur.execute("SELECT slot, rfid, waktu_masuk FROM parkir_db ORDER BY waktu_masuk DESC")
    data_parkir = cur.fetchall()

    cur.execute("SELECT slot FROM parkir_db WHERE waktu_keluar IS NULL")
    occupied_slots = [row[0] for row in cur.fetchall()]

    cur.execute("SELECT COUNT(*) FROM parkir_db WHERE waktu_keluar IS NULL")
    slot_terisi = cur.fetchone()[0]

    total_slot = 12
    slot_kosong = total_slot - slot_terisi
    cur.close()

    return render_template('index.html',
                           data_parkir=data_parkir,
                           slot_terisi=slot_terisi,
                           slot_kosong=slot_kosong,
                           total_slot=total_slot,
                           occupied_slots=occupied_slots)


@app.route('/auto_entry', methods=['POST'])
def auto_entry():
    data = request.get_json()
    rfid = data.get('rfid')

    if not rfid:
        return jsonify({'error': 'RFID tidak ditemukan'}), 400

    waktu_masuk = datetime.now()
    cur = mysql.connection.cursor()

    cur.execute("SELECT id FROM parkir_db WHERE rfid = %s AND waktu_keluar IS NULL", (rfid,))
    if cur.fetchone():
        cur.close()
        return jsonify({'error': 'Kendaraan masih terparkir'}), 409

    cur.execute(SLOT_SQL)
    available_slot = cur.fetchone()

    if not available_slot:
        cur.close()
        return jsonify({'error': 'Slot parkir penuh'}), 503

    slot = available_slot[0]
    cur.execute("INSERT INTO parkir_db (rfid, waktu_masuk, slot) VALUES (%s, %s, %s)", (rfid, waktu_masuk, slot))
    mysql.connection.commit()
    cur.close()

    global latest_uid_entry
    latest_uid_entry = rfid

    return jsonify({'message': 'Kendaraan berhasil masuk', 'slot': slot}), 200

@app.route('/get_info')
def get_info():
    global latest_uid, last_uid_time
    rfid = request.args.get('rfid')

    now = time.time()
    if rfid == latest_uid and now - last_uid_time < 5:
        return jsonify({'error': 'Tunggu sebentar...'}), 429

    latest_uid = rfid
    last_uid_time = now

    cur = mysql.connection.cursor()
    cur.execute("""
        SELECT id, slot, waktu_masuk 
        FROM parkir_db 
        WHERE rfid = %s AND waktu_keluar IS NULL 
        ORDER BY waktu_masuk DESC 
        LIMIT 1
    """, (rfid,))
    data = cur.fetchone()

    if not data:
        return jsonify({'error': 'Data tidak ditemukan atau sudah keluar.'})

    id_parkir, slot, waktu_masuk = data
    waktu_keluar = datetime.now()
    durasi_jam = (waktu_keluar - waktu_masuk).total_seconds() / 3600
    tarif_per_jam = 5000
    tarif = int((durasi_jam // 1 + 1) * tarif_per_jam)

    return jsonify({
        'id': id_parkir,
        'slot': slot,
        'waktu_masuk': waktu_masuk.strftime('%Y-%m-%d %H:%M:%S'),
        'waktu_keluar': waktu_keluar.strftime('%Y-%m-%d %H:%M:%S'),
        'tarif': tarif
    })



@app.route('/check_latest_uid')
def check_latest_uid():
    global latest_uid
    uid = latest_uid
    latest_uid = None
    return jsonify({'rfid': uid})

@app.route('/latest_slot')
def latest_slot():
    global latest_uid_entry
    if not latest_uid_entry:
        return jsonify({'slot': None})

    cur = mysql.connection.cursor()
    cur.execute("""
        SELECT slot FROM parkir_db 
        WHERE rfid = %s AND waktu_keluar IS NULL 
        ORDER BY waktu_masuk DESC 
        LIMIT 1
    """, (latest_uid_entry,))
    result = cur.fetchone()
    cur.close()

    if result:
        return jsonify({'slot': result[0]})
    else:
        return jsonify({'slot': None})

@app.route('/check_entry_uid')
def check_entry_uid():
    global latest_uid_entry
    uid = latest_uid_entry
    latest_uid_entry = None
    return jsonify({'rfid': uid})

@app.route('/confirm_exit', methods=['POST'])
def confirm_exit():
    global last_confirmed_exit_uid
    data = request.get_json()
    rfid = data['id']

    last_confirmed_exit_uid = rfid  # Simpan UID untuk dicek oleh ESP32

    # Hapus dari database seperti biasa
    cur = mysql.connection.cursor()
    cur.execute("""
        DELETE FROM parkir_db 
        WHERE id = (
            SELECT id FROM (
                SELECT id FROM parkir_db 
                WHERE rfid = %s AND waktu_keluar IS NULL 
                ORDER BY waktu_masuk DESC 
                LIMIT 1
            ) AS subquery
        )
    """, (rfid,))
    mysql.connection.commit()
    cur.close()
    return '', 200

@app.route('/cek_keluar/<uid>', methods=['GET'])
def cek_konfirmasi_keluar(uid):
    global last_confirmed_exit_uid
    if last_confirmed_exit_uid and uid == last_confirmed_exit_uid:
        last_confirmed_exit_uid = None  # Reset setelah dicek
        return jsonify({'status': True})
    return jsonify({'status': False})


@app.route('/get_confirmed_exit_uid', methods=['GET'])
def get_confirmed_exit_uid():
    return jsonify({'uid': last_confirmed_exit_uid})


@app.route('/cek_keluar/<string:rfid>', methods=['GET'])
def cek_keluar(rfid):
    # Cek apakah ada data dengan rfid yang masih belum keluar (waktu_keluar IS NULL)
    cur = mysql.connection.cursor()
    cur.execute("SELECT id FROM parkir_db WHERE rfid=%s AND waktu_keluar IS NULL", (rfid,))
    data = cur.fetchone()
    cur.close()

    if data:
        # Belum keluar, berarti belum bisa konfirmasi keluar
        return jsonify("false")
    else:
        # Data sudah keluar / tidak ada, berarti bisa buka palang
        return jsonify("true")

@app.route('/konfirmasi_keluar', methods=['POST'])
def konfirmasi_keluar():
    data = request.get_json()
    rfid = data.get('rfid')
    now = datetime.now()

    cur = mysql.connection.cursor()
    # Update data parkir keluar (waktu_keluar) untuk rfid yang masih belum keluar
    cur.execute("UPDATE parkir_db SET waktu_keluar=%s WHERE rfid=%s AND waktu_keluar IS NULL", (now, rfid))
    mysql.connection.commit()
    updated = cur.rowcount
    cur.close()

    if updated > 0:
        return jsonify({"message": "Konfirmasi keluar berhasil"})
    else:
        return jsonify({"message": "Data RFID tidak ditemukan atau sudah keluar"}), 404

@app.route('/bantuan', methods=['POST'])
def bantuan():
    global bantuan_aktif
    bantuan_aktif = True
    print("Permintaan bantuan diterima!")
    return jsonify({'message': 'Bantuan diterima'}), 200


@app.route('/status_bantuan')
def status_bantuan():
    global bantuan_aktif
    return jsonify({'bantuan': bantuan_aktif})

@app.route('/reset_bantuan', methods=['POST'])
def reset_bantuan():
    global bantuan_aktif
    bantuan_aktif = False
    return jsonify({'message': 'Bantuan direset'}), 200


@app.route('/get_assigned_slot')
def get_assigned_slot():
    rfid = request.args.get('rfid')
    if not rfid:
        return jsonify({'error': 'RFID tidak ada'}), 400

    cur = mysql.connection.cursor()
    cur.execute("""
        SELECT slot FROM parkir_db
        WHERE rfid = %s AND waktu_masuk IS NULL
        ORDER BY waktu_masuk DESC LIMIT 1
    """, (rfid,))
    slot = cur.fetchone()
    cur.close()

    if slot is not None:
        return jsonify({'slot': slot[0]})
    else:
        # Bila tidak ada data, kembalikan slot default atau error
        return jsonify({'slot': 'A2'})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']

        if username == USERNAME_ADMIN and password == PASSWORD_ADMIN:
            session['admin_logged_in'] = True
            return redirect(url_for('index'))
        else:
            flash('Username atau password salah')
            return redirect(url_for('login'))

    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('admin_logged_in', None)
    return redirect(url_for('login'))

from flask import jsonify

@app.route('/occupied_slots')
def get_occupied_slots():
    cur = mysql.connection.cursor()
    cur.execute("SELECT slot FROM parkir_db WHERE waktu_keluar IS NULL")
    occupied_slots = [row[0] for row in cur.fetchall()]
    cur.close()
    return jsonify(occupied_slots)

@app.route('/input_masuk', methods=['POST'])
def input_masuk():
    global servo_masuk_status
    servo_masuk_status = True  # tandai palang masuk harus dibuka
    return jsonify({'message': 'Permintaan buka palang masuk diterima'})

@app.route('/cek_servo_masuk')
def cek_servo_masuk():
    global servo_masuk_status
    if servo_masuk_status:
        servo_masuk_status = False  # reset status
        return jsonify({'buka': True})
    else:
        return jsonify({'buka': False})


@app.route('/')
def public_page():
    cur = mysql.connection.cursor()
    cur.execute("SELECT slot FROM parkir_db WHERE waktu_keluar IS NULL")
    occupied_slots = [row[0] for row in cur.fetchall()]
    slot_terisi = len(occupied_slots)
    total_slot = 12
    slot_kosong = total_slot - slot_terisi
    cur.close()

    return render_template('public.html',
                           slot_terisi=slot_terisi,
                           slot_kosong=slot_kosong,
                           total_slot=total_slot,
                           occupied_slots=occupied_slots)

if __name__ == '__main__':
    app.run(debug=True)
