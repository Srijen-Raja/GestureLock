import serial
import csv
import time
from datetime import datetime

# =========================================================
# CONFIGURATION
# =========================================================
COM_PORT = 'COM11'
BAUD_RATE = 115200
OUTPUT_FILE = 'jstk2_dataset.csv'

def start_data_collection():
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1)
        print(f"Connected to ZedBoard on {COM_PORT} at {BAUD_RATE} baud.")
        print(f"Recording data to '{OUTPUT_FILE}'... (Terminal print rate: 1 Hz). Press Ctrl+C to stop.\n")

        ser.reset_input_buffer()

        sample_count = 0
        last_print_time = time.time()

        with open(OUTPUT_FILE, mode='w', newline='') as file:
            writer = csv.writer(file)
            writer.writerow(['Timestamp', 'X_Axis', 'Y_Axis', 'Buttons'])

            while True:
                raw_line = ser.readline().decode('utf-8', errors='ignore').strip()

                if not raw_line or "Starting" in raw_line:
                    continue

                parts = raw_line.split(',')
                if len(parts) == 3:
                    try:
                        x_val = int(parts[0])
                        y_val = int(parts[1])
                        btn_val = int(parts[2])

                        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                        
                        # Save EVERY sample to CSV at full speed
                        writer.writerow([timestamp, x_val, y_val, btn_val])
                        sample_count += 1

                        # Update terminal display ONLY once per second (1 Hz)
                        current_time = time.time()
                        if current_time - last_print_time >= 1.0:
                            print(f"\rSamples Saved: {sample_count:6d} | Current X: {x_val:4d} | Y: {y_val:4d} | Buttons: {btn_val:2d}", end='')
                            last_print_time = current_time

                    except ValueError:
                        continue

    except serial.SerialException as e:
        print(f"\n[Error] Could not open port {COM_PORT}. Check connection or update COM_PORT in script.")
        print(f"Details: {e}")
    except KeyboardInterrupt:
        print(f"\n\nData collection stopped.")
        print(f"Successfully recorded {sample_count} samples to '{OUTPUT_FILE}'.")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Serial connection closed cleanly.")

if __name__ == '__main__':
    start_data_collection()