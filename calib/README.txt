校准文件不包含在仓库中。请在 Fudaa-LSPIV 中完成站点校准，再将同一工程 `outputs.dir` 中的以下文件复制到本目录：

  GRP.dat        控制点，用于生成 coeff.dat
  img_ref.dat    正射范围与分辨率
  PIV_param.dat  PIV 参数
  grid.dat       计算网格
  h.dat          正射高程/水位输入

可选文件：

  filters.dat    后处理滤波配置；缺少时跳过滤波

运行时，工具会将校准文件复制到本次结果目录的 `resolved_calib/`。若其中没有有效的 `coeff.dat`，会根据 `GRP.dat` 生成。原始校准目录不会被修改。

请勿将真实站点的校准文件提交到版本库；这些文件包含控制点、测区范围等站点信息。
