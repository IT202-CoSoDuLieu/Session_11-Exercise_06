-- PHÂN TÍCH & THIẾT KẾ
   -- 1. I/O: 
      -- - IN: p_patient_id, p_medicine_id, p_quantity, p_discount_code.
      -- - OUT: p_status_message (Dùng OUT để trả phản hồi trực tiếp cho App/Frontend).
   -- 2. LUỒNG XỬ LÝ:
      -- - Biến cục bộ: v_stock, v_price, v_final (Lưu trữ dữ liệu tạm để tính toán).
      -- - Bước 1: Lấy stock, price từ bảng Medicines.
      -- - Bước 2: Nếu v_stock < p_quantity -> Báo lỗi & Dừng.
      -- - Bước 3: Tính tiền; Giảm 50% nếu mã là 'NV-RIKKEI', còn lại tính giá gốc.
      -- - Bước 4: Trừ tồn kho Medicines & Cộng dồn total_due tại Patient_Invoices.
      -- - Bước 5: Trả thông báo thành công.
      
DROP DATABASE IF EXISTS  RikkeiClinicDB;
CREATE DATABASE RikkeiClinicDB;
USE RikkeiClinicDB;

CREATE TABLE Patients (
    patient_id INT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) UNIQUE NOT NULL,
    date_of_birth DATE
);

CREATE TABLE Employees (
    employee_id INT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    position VARCHAR(50) NOT NULL,
    salary DECIMAL(18,2) NOT NULL
);

CREATE TABLE Departments (
    dept_id INT PRIMARY KEY,
    dept_name VARCHAR(100) NOT NULL
);

CREATE TABLE Beds (
    bed_id INT PRIMARY KEY,
    dept_id INT NOT NULL,
    patient_id INT DEFAULT NULL,
    is_locked TINYINT DEFAULT 0,
    FOREIGN KEY (dept_id) REFERENCES Departments(dept_id),
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id)
);

CREATE TABLE Appointments (
    appointment_id INT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    appointment_date DATETIME NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id) REFERENCES Employees(employee_id)
);

CREATE TABLE Inventory (
    item_id INT PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0
);

CREATE TABLE Medicines (
    medicine_id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(18,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0
);

CREATE TABLE Patient_Invoices (
    patient_id INT PRIMARY KEY,
    total_due DECIMAL(18,2) NOT NULL DEFAULT 0,
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id)
);

INSERT INTO Patients VALUES (1, 'Nguyen Van An', '0901111222', '1990-05-15'), (2, 'Tran Thi Binh', '0912222333', '1985-08-20'), (3, 'Le Hoang Cuong', '0923333444', '2000-12-01');
INSERT INTO Employees VALUES (101, 'Dr. Hoang Minh', 'Doctor', 20000.00), (102, 'Dr. Lan Anh', 'Doctor', 25000.00), (103, 'Nurse Thu Ha', 'Nurse', 12000.00);
INSERT INTO Departments VALUES (1, 'Khoa Ngoai'), (2, 'Khoa Noi'), (3, 'Khoa ICU');
INSERT INTO Beds (bed_id, dept_id, patient_id, is_locked) VALUES (101, 1, 1, 1), (201, 2, NULL, 0), (301, 3, 2, 1);
INSERT INTO Appointments VALUES (104, 1, 101, '2026-06-10 08:30:00', 'Pending'), (105, 2, 102, '2026-05-01 09:00:00', 'Completed'), (106, 3, 101, '2026-05-02 10:00:00', 'Cancelled');
INSERT INTO Inventory VALUES (10, 'Khau trang y te N95', 1000), (11, 'Gang tay vo trung', 500), (12, 'Dung dich sat khuan', 200);
INSERT INTO Medicines VALUES (1, 'Amoxicillin 500mg', 15000, 100), (2, 'Panadol Extra', 5000, 5);
INSERT INTO Patient_Invoices VALUES (1, 1500000.00, NOW()), (2, 0, NOW()), (3, 0, NOW());

DROP PROCEDURE IF EXISTS CancelAppointment;
DELIMITER //
CREATE PROCEDURE CancelAppointment(IN p_appointment_id INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM Appointments WHERE appointment_id = p_appointment_id;
    IF v_status = 'Pending' THEN
        UPDATE Appointments SET status = 'Cancelled' WHERE appointment_id = p_appointment_id;
        SELECT 'Thành công: Lịch khám đã được hủy.' AS Message;
    ELSE
        SELECT CONCAT('Lỗi: Không thể hủy lịch khám đang ở trạng thái ', IFNULL(v_status, 'không tồn tại')) AS Message;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS AddInventory;
DELIMITER //
CREATE PROCEDURE AddInventory(IN p_item_id INT, IN p_quantity INT)
BEGIN
    IF p_quantity <= 0 THEN
        SELECT 'Lỗi: Số lượng nhập kho phải lớn hơn 0!' AS Message;
    ELSE
        UPDATE Inventory SET stock_quantity = stock_quantity + p_quantity WHERE item_id = p_item_id;
        SELECT 'Thành công: Đã cập nhật số lượng nhập kho.' AS Message;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS CalculateDischargeCost;
DELIMITER //
CREATE PROCEDURE CalculateDischargeCost(
    IN p_total_cost DECIMAL(18,2),
    IN p_patient_type VARCHAR(20),
    OUT p_final_amount DECIMAL(18,2),
    OUT p_status_message VARCHAR(255)
)
BEGIN
    IF p_total_cost <= 0 THEN
        SET p_final_amount = 0;
        SET p_status_message = 'Lỗi: Chi phí không hợp lệ';
    ELSE
        CASE p_patient_type
            WHEN 'BHYT' THEN SET p_final_amount = p_total_cost * 0.2;
            WHEN 'VIP' THEN SET p_final_amount = p_total_cost * 0.9;
            ELSE SET p_final_amount = p_total_cost;
        END CASE;
        SET p_status_message = 'Đã tính toán xong';
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS GetPatientDebt;
DELIMITER //
CREATE PROCEDURE GetPatientDebt(
    IN p_patient_id INT,
    IN p_phone VARCHAR(15),
    OUT p_total_debt DECIMAL(18,2),
    OUT p_status_message VARCHAR(255)
)
BEGIN
    DECLARE v_found_id INT;
    IF p_patient_id IS NULL AND p_phone IS NULL THEN
        SET p_total_debt = 0; SET p_status_message = 'Lỗi: Vui lòng nhập ID hoặc Số điện thoại';
    ELSE
        SELECT patient_id INTO v_found_id FROM Patients WHERE patient_id = p_patient_id OR phone = p_phone LIMIT 1;
        IF v_found_id IS NOT NULL THEN
            SELECT total_due INTO p_total_debt FROM Patient_Invoices WHERE patient_id = v_found_id;
            SET p_status_message = 'Tra cứu thành công';
        ELSE
            SET p_total_debt = 0; SET p_status_message = 'Không tìm thấy thông tin bệnh nhân';
        END IF;
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS FindAvailableBed;
DELIMITER //
CREATE PROCEDURE FindAvailableBed(IN p_dept_id INT, OUT p_bed_id INT)
BEGIN
    SELECT bed_id INTO p_bed_id FROM Beds WHERE dept_id = p_dept_id AND patient_id IS NULL AND is_locked = 0 LIMIT 1;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS TransferPatient;
DELIMITER //
CREATE PROCEDURE TransferPatient(IN p_patient_id INT, IN p_target_dept_id INT, OUT p_new_bed_id INT, OUT p_status_message VARCHAR(255))
BEGIN
    DECLARE v_found_bed_id INT;
    CALL FindAvailableBed(p_target_dept_id, v_found_bed_id);
    IF v_found_bed_id IS NULL THEN
        SET p_new_bed_id = NULL; SET p_status_message = 'Từ chối: Khoa chuyển đến đã hết giường';
    ELSE
        UPDATE Beds SET patient_id = NULL, is_locked = 0 WHERE patient_id = p_patient_id;
        UPDATE Beds SET patient_id = p_patient_id, is_locked = 1 WHERE bed_id = v_found_bed_id;
        SET p_new_bed_id = v_found_bed_id; SET p_status_message = 'Thành công: Đã chuyển khoa';
    END IF;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS ProcessPrescription;
DELIMITER //
CREATE PROCEDURE ProcessPrescription(
    IN p_patient_id INT, IN p_medicine_id INT, IN p_quantity INT, IN p_discount_code VARCHAR(20), OUT p_status_message VARCHAR(255)
)
BEGIN
    DECLARE v_stock INT; DECLARE v_price DECIMAL(18,2); DECLARE v_final DECIMAL(18,2);
    SELECT stock, price INTO v_stock, v_price FROM Medicines WHERE medicine_id = p_medicine_id;
    IF v_stock < p_quantity THEN
        SET p_status_message = 'Thất bại: Kho không đủ thuốc';
    ELSE
        SET v_final = (p_quantity * v_price) * (CASE WHEN p_discount_code = 'NV-RIKKEI' THEN 0.5 ELSE 1 END);
        UPDATE Medicines SET stock = stock - p_quantity WHERE medicine_id = p_medicine_id;
        UPDATE Patient_Invoices SET total_due = total_due + v_final WHERE patient_id = p_patient_id;
        SET p_status_message = 'Thành công: Đã xử lý đơn thuốc';
    END IF;
END //
DELIMITER ;

--  KIỂM THỬ (TEST CASES)
CALL CancelAppointment(105); -- Test hủy lịch đã hoàn thành
CALL AddInventory(10, -500); -- Test nhập số âm
CALL GetPatientDebt(NULL, '0901111222', @debt, @msg); SELECT @debt, @msg; -- Tra cứu nợ
CALL TransferPatient(1, 2, @bed, @st); SELECT @bed, @st; -- Chuyển khoa (1 sang 2)
CALL ProcessPrescription(1, 1, 5, 'NV-RIKKEI', @res); SELECT @res; -- Kê đơn giảm giá 50%