# Kiểm chứng v3: ngành khách sạn, 10 nhóm ràng buộc

Julia 1.10.10; JuMP 1.32.1; HiGHS.jl 1.26.1.
Input giả lập: 12 tên tiếng Anh, 2 team khách sạn, 30 ngày tháng 6/2026; mỗi team 2 Shift Supervisor.

## Đã chạy

- Import workbook bằng XLSX.jl, chuẩn hóa JSON và đối chiếu dữ liệu.
- Render và kiểm tra 3 sheet Excel, mã ca/ngày/tên/role/cấu hình mới.
- 10 nhóm kiểm thử, tổng 85 assertions đạt; gồm 76 regression/input-tháng và 9 kiểm tra R7–R10.
- Kiểm tra từng điều kiện mới có phát hiện lịch vi phạm; kiểm tra trường hợp thiếu supervisor bắt buộc báo INFEASIBLE.
- Giải từ workbook mặc định: OPTIMAL, objective=920, shortage=0, preference_violations=92, hour_deviation=0, hard_constraint_violations=0.
- Tổng giờ mỗi người 160. Đã kiểm tra độc lập từ assignments: mọi cửa sổ 7 ngày ≤40h; mỗi người ≤14 ca tối, ≤6 ngày cuối tuần; mọi team/ngày có ≥1 supervisor.

## Giới hạn

Kết quả trên chứng minh bộ input mẫu có thể thỏa các ràng buộc cùng lúc. Không bảo đảm mọi input tùy ý đều khả thi. Role Shift Supervisor được kiểm soát theo ngày, không theo mọi khung giờ. Chưa xét chuyển tiếp giữa hai tháng. R3 vẫn là nhu cầu mềm.

Mục tiêu v3 bằng mục tiêu v2 không có nghĩa các điều kiện mới trùng lặp: nghiệm tối ưu cũ có thể không duy nhất và thêm điều kiện vẫn có thể giữ cùng giá trị mục tiêu. Xem docs/MODEL.md cho các ví dụ phân biệt R1–R10.
