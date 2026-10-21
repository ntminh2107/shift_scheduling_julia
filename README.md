# Xếp lịch nhân viên theo tháng bằng Julia

Bản v3 dùng bố cục Excel theo mẫu: nhu cầu theo team và đăng ký dạng nhân viên × ngày. Bộ mẫu giả lập có 12 người, 2 team Front Desk/Guest Services, 5 ca, đủ 30 ngày tháng 6/2026. Tên tiếng Anh giả lập và role ngành khách sạn được chọn bằng seed 20261021; không dùng danh sách người thật trong mẫu nguồn.

## Chạy project

```bash
julia --project=. setup.jl
julia --project=. main.jl --input data/input.xlsx --output results --export-lp
julia --project=. test/runtests.jl
```

Cần Julia 1.10 trở lên. Lần đầu tải dependency cần Internet. Không cần Python/Node để nhập Excel, giải mô hình hoặc xuất kết quả. Manifest.toml khóa dependency đã dùng.

## Nhập dữ liệu: chỉ 3 sheet

### Nguyện vọng nhân sự

Mỗi người một dòng từ dòng 3; dòng 1 là tiêu đề/ngày Excel, dòng 2 hiển thị thứ. A:I lần lượt là Mã NV, Tên, Team, Role, Không xếp, Ca được phép, Giờ tối thiểu, Giờ mục tiêu, Giờ tối đa. Ngày bắt đầu ở J1.

- Mã NV là khóa duy nhất. Tên có thể trùng, ID không được trùng.
- Role `Shift Supervisor` tham gia R10: mỗi team/ngày phải có ít nhất 1 supervisor đi làm. Mỗi team mẫu có 2 supervisor. Các role còn lại là Receptionist, Concierge, Reservations Agent.
- Ca được phép: `S1, S2, S3, G1, G2`; để trống nghĩa là mọi ca.
- Không xếp: 0 = tham gia; 1 = nghỉ cả tháng và bỏ yêu cầu giờ bằng cách chuẩn hóa min/target/max thành 0.
- Giờ tối thiểu/mục tiêu/tối đa đều tính cho toàn tháng. Mẫu 120/160/184 là giả định để test, chỉnh trực tiếp theo từng người.

| Ô đăng ký ngày | Cách hiểu |
|---|---|
| Trống | Có thể đi làm, mọi ca được phép đều được xem là phù hợp |
| 0 hoặc OFF | Nghỉ bắt buộc |
| S1 | Mong muốn ca S1 |
| S1 or S2 | Mong muốn S1 hoặc S2 |
| G1 | Mong muốn ca ngắn G1 |
| n | Mong muốn ca dài ít nhất 8 giờ, bắt đầu trước 14h, trong danh sách được phép |

Nguyện vọng là mềm: solver có thể chọn ca khác được phép và chịu phạt. Nghỉ vẫn là lựa chọn nếu có thể đi làm. Đăng ký ca không được phép hoặc mã không tồn tại sẽ báo lỗi có vị trí dòng/cột. Không hỗ trợ mã `%HT`, KL hay ca đêm của mô hình cũ.

Muốn đổi tháng: thay các ngày ở hàng 1 từ J trở đi bằng đầy đủ ngày của tháng mới; thêm/bớt cột cho đúng 28/29/30/31 ngày, sửa hàng thứ cho dễ đọc và cập nhật đăng ký/giờ tháng. Chương trình kiểm tra đủ một tháng, không chỉ đếm 30 cột. Có thể nhập ngày Excel hoặc chữ yyyy-mm-dd / dd/mm/yyyy. Xóa cột ngày không dùng, không để đăng ký dưới tiêu đề trống.

Muốn thêm người: thêm một dòng có Mã NV mới, đầy đủ A:I và các ngày. Không cần nhập thêm hàng ở bảng Availability/Preferences như bản cũ.

### Nhu cầu nhân sự

Giữ cấu trúc STT, Team, Nội dung, Kí hiệu, Nhu cầu nhân sự như mẫu. Nội dung là **khung giờ cần người**, ví dụ 06:00-10:00; K1–K4 là mã khung. Số người được áp dụng cho mỗi ngày trong tháng. Team phải khớp bảng nhân viên; cần đủ mọi team × khung, kể cả số 0. Team có thể điền mỗi dòng hoặc chỉ ở đầu nhóm.

Đây không phải nhu cầu số người nhận đúng một mã ca. Một ca 8 giờ có thể phục vụ hai khung. Việc giữ nhu cầu theo khung giúp giữ nguyên mô hình MILP đã xây dựng. Nếu cần nhu cầu thay đổi từng ngày, dùng JSON chuẩn hóa với bảng Demand; workbook gọn hiện áp dụng nhu cầu cố định mỗi ngày.

### List ràng buộc

- A1:D: bảng ca với giờ số (6 nghĩa là 06:00). Chỉ ca trong ngày, chưa hỗ trợ qua nửa đêm.
- G1:H: trọng số 100/10/1, max_consecutive=5, time_limit=60 giây, mip_gap=0.
- J:K: hướng dẫn nhập và các rule thực sự được áp dụng.

Giữ tiêu đề và vị trí các bảng. Phần mô tả rule là hướng dẫn; sửa chữ mô tả không sửa logic solver. Nếu thêm ca, bảo đảm ranh giới ca khớp khung nhu cầu. R5 vẫn là cấm kết thúc 22h rồi bắt đầu 06h hôm sau.

## Mô hình tháng

Giải đồng thời toàn bộ tháng. R1–R6 giữ nguyên cấu trúc, thêm R7–R10; hàm mục tiêu không đổi; tổng giờ/mục tiêu là tổng tháng. Giới hạn 5 ngày liên tiếp áp dụng mọi cửa sổ 6 ngày, kể cả qua ranh giới tuần. Chưa xét tháng trước/sau; không có hạn mức giờ riêng cho từng tuần.

Nhu cầu có biến thiếu và phạt; trọng số không bảo đảm đủ người tuyệt đối. Role Shift Supervisor được sử dụng trong R10. Xem docs/MODEL.md và src/model.jl để viết báo cáo.

## Kết quả và chuyển JSON

results/schedule.csv: bảng lịch nhân viên × ngày; assignments.csv: từng ngày có ngày lịch; hours.csv: tổng giờ tháng; coverage.csv: nhu cầu/thiếu/dư; result.json: trạng thái, gap, KPI, phiên bản. Tên và role có trong lịch, phân công và thống kê giờ. CSV dùng UTF-8 BOM để mở tiếng Việt bằng Excel. model.lp chỉ có khi dùng --export-lp.

```bash
julia --project=. generate_input.jl data/input.xlsx data/input.json
julia --project=. main.jl --input data/input.json --output results_json
```

JSON đi kèm là snapshot của Excel lúc giao. Sau khi sửa Excel phải chạy generate_input.jl để đồng bộ nếu muốn dùng JSON. Excel luôn là input mặc định.

Các test/fixtures/legacy.xlsx và legacy.json chỉ phục vụ regression bản tuần cũ. sample_input() là fixture cũ, không phải input tháng. reference_python/result.json là tham chiếu bản tuần, không so trực tiếp với kết quả tháng. scripts/compare_python.jl yêu cầu truyền rõ hai file của cùng kịch bản.

src/template_input.jl chuyển 3 sheet tiếng Việt thành schema nội bộ, src/input.jl kiểm tra dữ liệu, src/results.jl kiểm chứng lại nghiệm độc lập. Giữ đọc được schema Excel 8 sheet/JSON cũ để regression.

## Bốn điều kiện mới (v3)

Bảng Config có thêm 4 khóa, phải có đủ cả 4: max_hours_7days=40, max_late_shifts=14, max_weekend_days=6, min_supervisors_per_day=1. Tất cả là ràng buộc cứng. Đọc docs/MODEL.md để xem đủ 10 nhóm công thức và giải thích vì sao không trùng lặp. Dữ liệu legacy chỉ có 6 khóa cũ vẫn chạy chế độ R1–R6 để regression; workbook mặc định v3 bật đủ R1–R10.

Khi đổi role, giữ chính xác `Shift Supervisor` nếu nhân viên đủ điều kiện giám sát. Role không tự cấp quyền nhận mọi ca; R2 vẫn áp dụng. Đổi input có thể khiến vô nghiệm, đặc biệt nếu thiếu supervisor vào một ngày. Không có bảo đảm khả thi cho mọi dữ liệu tùy ý.
# shift_scheduling_julia
