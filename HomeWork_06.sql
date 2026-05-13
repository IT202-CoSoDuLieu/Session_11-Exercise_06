/* 
   INPUT: Patient ID, Medicine ID, Quantity, Discount Code
   OUTPUT: Status Message (Type: OUT) - Trả về kết quả xử lý cho Frontend
   LOGIC: 
     1. Dùng Local Variables lưu trữ stock/price/amount tạm thời để tính toán.
     2. Chặn giao dịch nếu stock < quantity.
     3. Tự động xử lý mã giảm giá 'NV-RIKKEI' (giảm 50%) hoặc mặc định giá gốc nếu mã lỗi/NULL.
     4. Cập nhật đồng thời tồn kho và công nợ bệnh nhân.
*/

CREATE DATABASE homework06;
USE homework06;

CREATE TABLE Medicines (
    medicine_id INT PRIMARY KEY,
    name VARCHAR(100),
    price DECIMAL(18,2),
    stock INT
);

CREATE TABLE Patient_Invoices (
    patient_id INT PRIMARY KEY,
    total_due DECIMAL(18,2) DEFAULT 0
);

INSERT INTO Medicines VALUES (1, 'Panadol', 5000, 100), (2, 'Antibiotic', 20000, 10);
INSERT INTO Patient_Invoices VALUES (1, 0), (2, 50000);

DROP PROCEDURE IF EXISTS ProcessPrescription;
DELIMITER //

CREATE PROCEDURE ProcessPrescription(
    IN p_patient_id INT,
    IN p_medicine_id INT,
    IN p_quantity INT,
    IN p_discount_code VARCHAR(20),
    OUT p_status_message VARCHAR(255) -- Tham số trả về thông báo trạng thái
)
BEGIN
    -- Sử dụng các biến cục bộ để lưu trữ dữ liệu tạm thời
    DECLARE v_current_stock INT;
    DECLARE v_price DECIMAL(18,2);
    DECLARE v_total_cost DECIMAL(18,2);
    DECLARE v_final_amount DECIMAL(18,2);

    SELECT stock, price INTO v_current_stock, v_price 
    FROM Medicines 
    WHERE medicine_id = p_medicine_id;

    IF v_current_stock < p_quantity THEN
        SET p_status_message = 'Thất bại: Kho không đủ thuốc';
    ELSE
        SET v_total_cost = p_quantity * v_price;
        
        IF p_discount_code = 'NV-RIKKEI' THEN
            SET v_final_amount = v_total_cost * 0.5;
        ELSE
            SET v_final_amount = v_total_cost;
        END IF;

        UPDATE Medicines 
        SET stock = stock - p_quantity 
        WHERE medicine_id = p_medicine_id;

        UPDATE Patient_Invoices 
        SET total_due = total_due + v_final_amount 
        WHERE patient_id = p_patient_id;

        SET p_status_message = 'Thành công: Đã xử lý đơn thuốc';
    END IF;
END //

DELIMITER ;

-- 1. Kê đơn bình thường (không có mã giảm giá)
CALL ProcessPrescription(1, 1, 10, NULL, @msg1);
SELECT @msg1 AS Result;

-- 2. Kê đơn có mã NV-RIKKEI (giảm 50%)
CALL ProcessPrescription(1, 1, 2, 'NV-RIKKEI', @msg2);
SELECT @msg2 AS Result;

-- 3. Kê đơn vượt quá số lượng tồn kho (Bẫy 1)
CALL ProcessPrescription(2, 2, 50, 'NV-RIKKEI', @msg3);
SELECT @msg3 AS Result;