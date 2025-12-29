enum NewsSetRetentionOption {
  keep(null, '削除しない'),
  days1(1, '1日前より古い項目削除'),
  days3(3, '3日前より古い項目削除'),
  days7(7, '7日前より古い項目削除'),
  days30(30, '30日前より古い項目削除'),
  days90(90, '90日前より古い項目削除'),
  days180(180, '180日前より古い項目削除');

  const NewsSetRetentionOption(this.days, this.label);

  final int? days;
  final String label;
}
