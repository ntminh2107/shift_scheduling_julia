# Mô hình toán và ánh xạ sang Julia

## Tập hợp

- A: nhân viên, chỉ số a.
- B={1,…,N}: ngày, chỉ số b.
- C: team, chỉ số c. A_c là nhân viên thuộc team c.
- S={S1,S2,S3,G1,G2}: ca làm, chỉ số s.
- K={K1,K2,K3,K4}: khung nhu cầu, chỉ số k.

Biến quyết định:

$$x_{abs}\in\{0,1\},\quad u_{bck}\ge0,\quad z_a\ge0.$$

x chỉ ra việc xếp ca; u là thiếu nhân sự; z là lệch giờ. Không cần chiều team trong x vì team cố định theo nhân viên. OFF tương ứng tổng x trong ngày bằng 0.

Tham số: v_ab là ngày có thể đi làm; e_abs là quyền nhận ca; p_abs là ca mong muốn; h_s là số giờ; d_bck là nhu cầu; q_sk là hệ số bao phủ; Hmin/Hmax/H* là giới hạn/mục tiêu giờ; L là giới hạn chuỗi ngày làm.

$$w_{ab}=\sum_s x_{abs},\quad H_a=\sum_{b,s}h_sx_{abs},\quad n_{bck}=\sum_{a\in A_c,s}q_{sk}x_{abs}.$$

## Ràng buộc

R1: tối đa một ca/ngày và nghỉ đúng ngày không khả dụng:

$$\sum_s x_{abs}\le v_{ab}\quad\forall a,b.$$

R2: chỉ ca được phép:

$$x_{abs}\le e_{abs}\quad\forall a,b,s.$$

Trong JuMP, R2 được đặt bằng `set_upper_bound`, vẫn là ràng buộc cứng.

R3: nhu cầu mềm có biến thiếu:

$$n_{bck}+u_{bck}\ge d_{bck}\quad\forall b,c,k.$$

R4: giờ làm:

$$H_a^{\min}\le H_a\le H_a^{\max}\quad\forall a.$$

R5: cấm kết thúc 22h rồi bắt đầu 6h hôm sau:

$$\sum_{s\in S^{late}}x_{abs}+\sum_{s\in S^{early}}x_{a,b+1,s}\le1\quad\forall a, b<N.$$

S_late={S3,G2}, S_early={S1,G1} trong bộ ca mẫu. Code xác định từ end=22 và start=6.

R6: trong L+1 ngày phải có ít nhất một ngày nghỉ:

$$\sum_{t=b}^{b+L}w_{at}\le L\quad\forall a,b=1,\ldots,N-L.$$

Nếu N≤L, không có cửa sổ đủ dài và không tạo R6. Không xét lịch trước kỳ hiện tại.

Tuyến tính hóa lệch giờ:

$$z_a\ge H_a-H_a^*,\quad z_a\ge H_a^*-H_a.$$

## Mục tiêu

$$\min Z=\lambda_1\sum_{b,c,k}u_{bck}+\lambda_2\sum_{a,b,s}(1-p_{abs})x_{abs}+\lambda_3\sum_a z_a.$$

Mẫu dùng λ1=100, λ2=10, λ3=1. Khi tối ưu với trọng số dương, u và z đạt phần thiếu và độ lệch tương ứng. Với nghiệm dừng sớm, biến phụ có thể còn dư; kết quả báo cả solver_objective lẫn objective_recomputed từ lịch.

Mọi biểu thức tuyến tính. Biến x nhị phân, u và z liên tục nên đây là MILP. Thiếu nhân sự tính theo người-khung; các khung mẫu có cùng độ dài 4 giờ. Nếu dùng khung dài ngắn khác nhau, hàm mục tiêu hiện vẫn tính mỗi người-khung như nhau.

## Mã nguồn liên quan

| Công thức | Vị trí |
|---|---|
| Tập và tham số | prepare_data trong src/input.jl |
| q_sk theo giờ | vòng lặp tính q trong src/input.jl |
| x,u,z | @variable trong src/model.jl |
| w,H,n | @expression trong src/model.jl |
| R1…R6 | Các khối được gắn nhãn trong src/model.jl |
| Trị tuyệt đối | deviation_above / deviation_below |
| Hàm mục tiêu | Z1 / Z2 / Z3 và @objective |
| Kiểm tra ràng buộc | verify_schedule và kiểm tra u,z trong src/results.jl |

## KPI

$$\text{coverage rate}=1-\frac{\sum_{b,c,k}[d_{bck}-n_{bck}]_+}{\sum_{b,c,k}d_{bck}}.$$

$$\text{preference rate}=1-\frac{\sum_{a,b,s}(1-p_{abs})x_{abs}}{\sum_{a,b,s}x_{abs}}.$$

$$\text{hour deviation}=\sum_a|H_a-H_a^*|,\quad\text{surplus}=\sum_{b,c,k}[n_{bck}-d_{bck}]_+.$$

KPI có mẫu số 0 trả về null, không gán giả thành 100%. Công thức không phạt một ngày nghỉ dù nhân viên có đăng ký ca mong muốn. Dư nhân sự chỉ được đo, không bị phạt trong mục tiêu.

## Bản tháng và input v2

Với workbook v2, B là toàn bộ ngày trong một tháng (28/29/30/31 ngày).
Bộ mẫu dùng tháng 6/2026, N=30. Giải đồng thời cả tháng, không tách tuần.
H_a và T_a là giờ TOÀN THÁNG; mẫu giả lập dùng min=120, target=160, max=184.
Đây là giả định học thuật có thể chỉnh ở từng nhân viên, không phải quy định pháp lý.
R6 dùng mọi cửa sổ 6 ngày trong tháng, không reset ở đầu tuần.
Không có ràng buộc giờ theo từng tuần; chưa nối lịch tháng trước/tháng sau.
Ở v3, role Shift Supervisor tham gia R10 (xem phần mở rộng bên dưới).
Ô nguyện vọng trống được mở rộng thành preferred=allowed (không phạt ca nào được phép).
0/OFF đặt available=0; Không xếp=1 đặt available=0 cả tháng và min/target/max=0.
Nhu cầu ở mẫu được lặp theo từng ngày, cùng đơn vị người-khung như R3.
Ca S1/S2/S3/G1/G2 dùng chung giữa các team. Không dùng lại mã ca 1..11/HT/KL của file gốc.

## Mở rộng v3: 10 nhóm ràng buộc nghiệp vụ

Bản v3 dùng ngành khách sạn, team Front Desk và Guest Services. Tên tiếng Anh giả lập không lấy từ input nguồn. Role `Shift Supervisor` xác định tập Q_c gồm supervisor của team c; các role khác là Receptionist, Concierge, Reservations Agent. Role giờ có tác dụng trong R10.

Giữ R1–R6 ở trên. Thêm bốn nhóm sau, đều là ràng buộc cứng:

R7 — giới hạn giờ trong mọi cửa sổ 7 ngày:
$$\sum_{t=b}^{b+6}\sum_{s\in S}h_sx_{ats}\le W\quad\forall a,\ b=1,\ldots,N-6.$$
Mẫu W=40 giờ. Không reset ở đầu tuần. R4 kiểm soát tổng tháng; R7 kiểm soát việc dồn giờ trong một giai đoạn ngắn.

R8 — giới hạn ca tối trong tháng:
$$\sum_{b\in B}\sum_{s\in S^{late}}x_{abs}\le M\quad\forall a.$$
Mẫu M=14; ca tối là ca kết thúc 22h, gồm S3 và G2. Đây là số lượt ca, không phải số giờ. R5 kiểm soát chuyển ca giữa hai ngày; R8 kiểm soát tổng gánh nặng ca tối.

R9 — giới hạn ngày làm cuối tuần:
$$\sum_{b\in B^{weekend}}w_{ab}\le V\quad\forall a.$$
B_weekend gồm thứ Bảy và Chủ nhật theo lịch thực tế; mẫu V=6 ngày. R6 giới hạn chuỗi ngày làm, còn R9 kiểm soát phân bổ ngày cuối tuần; chúng không thay thế nhau.

R10 — supervisor mỗi team/ngày:
$$\sum_{a\in Q_c}w_{ab}\ge P\quad\forall b,c.$$
Mẫu P=1; mỗi team có 2 supervisor trong input mẫu. Đếm số supervisor được phân công một ca trong ngày. Không đảm bảo supervisor có mặt cả ngày hay mọi khung giờ. R3 kiểm soát số người phục vụ; R10 kiểm soát thành phần nhân sự.

| Nhóm | Phạm vi kiểm soát | Loại |
|---|---|---|
| R1 | Tối đa 1 ca/ngày, nghỉ khi không khả dụng | Cứng |
| R2 | Chỉ nhận ca được phép | Cứng |
| R3 | Đáp ứng nhu cầu theo team/khung, cho phép thiếu có phạt | Mềm |
| R4 | Tổng giờ tháng trong min/max | Cứng |
| R5 | Cấm ca muộn rồi ca sớm hôm sau | Cứng |
| R6 | Giới hạn chuỗi ngày làm liên tiếp | Cứng |
| R7 | Giới hạn giờ trong mỗi 7 ngày | Cứng |
| R8 | Giới hạn số ca tối trong tháng | Cứng |
| R9 | Giới hạn số ngày làm cuối tuần | Cứng |
| R10 | Số supervisor tối thiểu mỗi team/ngày | Cứng |

Miền nhị phân và hai bất đẳng thức tuyến tính hóa z là điều kiện kỹ thuật bổ sung, không dùng để đếm đủ 10 nhóm nghiệp vụ. Hàm mục tiêu giữ nguyên ba thành phần phạt thiếu người, trái nguyện vọng, lệch giờ; không thêm trọng số phạt cho R7–R10 vì đây là điều kiện cứng.

### Vì sao không trùng lặp?

R7 đặt W=40 (không đặt 48, vì với tối đa 8h/ca và R6 giới hạn 5 ngày liên tiếp, 48h/7 ngày đã được suy ra). Ví dụ làm 3 ngày, nghỉ 1 ngày, làm tiếp 3 ngày: thỏa R6 nhưng 48h vi phạm R7.
R8 có thể bị vi phạm bởi 15 ca tối cách ngày, dù thỏa điều kiện chuyển ca và không có chuỗi làm dài. R9 có thể bị vi phạm khi làm 7 ngày cuối tuần, dù tổng giờ tháng và chuỗi ngày vẫn hợp lệ. R10 có thể bị vi phạm khi đủ số người nhưng tất cả đều không phải supervisor.

### Tính tương thích

Không có mâu thuẫn logic bắt buộc giữa các nhóm. Tuy nhiên, tính khả thi phụ thuộc input và giá trị ngưỡng. Ví dụ tất cả supervisor nghỉ cùng ngày sẽ vi phạm R10; đặt min_hours quá cao so với W và ngày nghỉ có thể làm R4/R7 không thể cùng thỏa. Không khẳng định khả thi cho mọi input, không tự nới ràng buộc để chữa vô nghiệm. Kiểm thử cả trường hợp có nghiệm và trường hợp mâu thuẫn có chủ đích. Nhu cầu mềm R3 không chữa được mâu thuẫn giữa các ràng buộc cứng.

Các cửa sổ vẫn chỉ xét bên trong tháng; chưa xét lịch tháng trước/sau. Ngưỡng là giả định học thuật, không phải diễn giải luật lao động.
