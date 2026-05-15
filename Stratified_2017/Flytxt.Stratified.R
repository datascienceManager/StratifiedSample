#' @title Stratified sample on whole base
#
#' @description  By facilitating the sample size , it would extract stratified sample from the whole data base
#
#' @param data
#
#' @param sample.size
#
#' @return data.table
#
#' @example Flytxt_Stratified(dataFrameName,500)
#'
#' @export  Flytxt_Stratified


Flytxt_Stratified = function (data, sample.size)
{
  if (is.null(data)) {
    stop("Data not provided. Please provide the dataset")
  }
  if (!is.null(data)) {

    combine_all <- data.table(data)


    ID_var = data.frame(seq(1,nrow(combine_all)))
    colnames(ID_var)[1] = c("ID_var")
    combine_all = cbind(ID_var,combine_all)


    combine_row <- nrow(data)
    combine_col <- ncol(data)


    if (is.null(sample.size)) {
      stop("Strata Sample size not provided. Please provide the strata sample size")
    }
    if (!is.null(sample.size)) {
      sample_size <- as.numeric(sample.size)
      # sample_size = 400
      sample_base <- nrow(data)
      per_sample <- round((sample_size/sample_base),
                          digits = 4)



      Numeric_data = data.frame(dplyr::select_if(combine_all,is.numeric))
      Factor_data = data.frame(dplyr::select_if(combine_all,is.factor))
      character_data=data.frame(dplyr::select_if(combine_all,is.character))

      f = function(x) {
        x <- as.numeric(as.character(x))
        x[is.na(x)] = 0
        x
      }
      StratifiedSamplingBGManjPra_1 <- data.frame(apply(Numeric_data[,
                                                                     1:ncol(Numeric_data)], 2, f))


      for (i in c(1:ncol(StratifiedSamplingBGManjPra_1))) {
        q = StratifiedSamplingBGManjPra_1[, i]
        Percentile_ <- quantile(q, c(0.99), na.rm = TRUE)
        StratifiedSamplingBGManjPra_1[, i][StratifiedSamplingBGManjPra_1[,
                                                                         i] > Percentile_] <- Percentile_
      }
      ColNames_ = colnames(StratifiedSamplingBGManjPra_1)


      Cal_Percentile = data.frame(1:10)
      for (i in c(1:ncol(StratifiedSamplingBGManjPra_1))) {
        q = StratifiedSamplingBGManjPra_1[, i]
        Percentile_ <- quantile(q, seq(from = 0.1,
                                       to = 1, by = 0.1))
        Cal_Percentile[paste("Percentile", ColNames_[i],
                             sep = "_")] <- round(Percentile_, digits = 2)
      }
      Cal_Percentile[, c("X1.10")] = NULL
      Percetn_value = seq(from = 0.1, to = 1, by = 0.1)
      Percetn_value = data.frame(Percetn_value)
      Cal_Percentile = cbind(Cal_Percentile, Percetn_value)
      for (col_ in 1:ncol(StratifiedSamplingBGManjPra_1)) {
        b = col_
        StratifiedSamplingBGManjPra_1[paste("Percet", ColNames_[col_],
                                            sep = "_")] <- ifelse(StratifiedSamplingBGManjPra_1[b] <
                                                                    Cal_Percentile[1, b], Cal_Percentile[1, ncol(Cal_Percentile)],
                                                                  ifelse(StratifiedSamplingBGManjPra_1[b] >= Cal_Percentile[1,
                                                                                                                            b] & StratifiedSamplingBGManjPra_1[b] < Cal_Percentile[2,
                                                                                                                                                                                   b], Cal_Percentile[1, ncol(Cal_Percentile)],
                                                                         ifelse(StratifiedSamplingBGManjPra_1[b] >= Cal_Percentile[2,
                                                                                                                                   b] & StratifiedSamplingBGManjPra_1[b] < Cal_Percentile[3,
                                                                                                                                                                                          b], Cal_Percentile[2, ncol(Cal_Percentile)],
                                                                                ifelse(StratifiedSamplingBGManjPra_1[b] >= Cal_Percentile[3,
                                                                                                                                          b] & StratifiedSamplingBGManjPra_1[b] < Cal_Percentile[4,
                                                                                                                                                                                                 b], Cal_Percentile[3, ncol(Cal_Percentile)],
                                                                                       ifelse(StratifiedSamplingBGManjPra_1[b] >= Cal_Percentile[4,
                                                                                                                                                 b] & StratifiedSamplingBGManjPra_1[b] < Cal_Percentile[5,
                                                                                                                                                                                                        b], Cal_Percentile[4, ncol(Cal_Percentile)],
                                                                                              ifelse(StratifiedSamplingBGManjPra_1[b] >=
                                                                                                       Cal_Percentile[5, b] & StratifiedSamplingBGManjPra_1[b] <
                                                                                                       Cal_Percentile[6, b], Cal_Percentile[5,
                                                                                                                                            ncol(Cal_Percentile)], ifelse(StratifiedSamplingBGManjPra_1[b] >=
                                                                                                                                                                            Cal_Percentile[6, b] & StratifiedSamplingBGManjPra_1[b] <
                                                                                                                                                                            Cal_Percentile[7, b], Cal_Percentile[6,
                                                                                                                                                                                                                 ncol(Cal_Percentile)], ifelse(StratifiedSamplingBGManjPra_1[b] >=
                                                                                                                                                                                                                                                 Cal_Percentile[7, b] & StratifiedSamplingBGManjPra_1[b] <
                                                                                                                                                                                                                                                 Cal_Percentile[8, b], Cal_Percentile[7,
                                                                                                                                                                                                                                                                                      ncol(Cal_Percentile)], ifelse(StratifiedSamplingBGManjPra_1[b] >=
                                                                                                                                                                                                                                                                                                                      Cal_Percentile[8, b] & StratifiedSamplingBGManjPra_1[b] <
                                                                                                                                                                                                                                                                                                                      Cal_Percentile[9, b], Cal_Percentile[8,
                                                                                                                                                                                                                                                                                                                                                           ncol(Cal_Percentile)], Cal_Percentile[9,
                                                                                                                                                                                                                                                                                                                                                                                                 ncol(Cal_Percentile)])))))))))
      }
      OnlyPercn = StratifiedSamplingBGManjPra_1 %>% dplyr::select(.,
                                                                  starts_with("Percet"))
      Col_OnlyPercn = colnames(OnlyPercn)
      # var_list

      # Now cbinding the numeric with factor or character column

      if(nrow(Factor_data)!= 0 & nrow(character_data)!=0){
        StratifiedSamplingBGManjPra_1= cbind(StratifiedSamplingBGManjPra_1[,c(1:length(ColNames_))],Factor_data,character_data,StratifiedSamplingBGManjPra_1[,c(((length(ColNames_))+1):ncol(StratifiedSamplingBGManjPra_1))])
      } else if (nrow(Factor_data)!= 0){
        StratifiedSamplingBGManjPra_1= cbind(StratifiedSamplingBGManjPra_1[,c(1:length(ColNames_))],Factor_data,StratifiedSamplingBGManjPra_1[,c(((length(ColNames_))+1):ncol(StratifiedSamplingBGManjPra_1))])
      } else if (nrow(character_data)!=0){
        StratifiedSamplingBGManjPra_1= cbind(StratifiedSamplingBGManjPra_1[,c(1:length(ColNames_))],character_data,StratifiedSamplingBGManjPra_1[,c(((length(ColNames_))+1):ncol(StratifiedSamplingBGManjPra_1))])
      }
    }


    stratified_sample_2_sep <- StratifiedSamplingBGManjPra_1 %>%
      group_by(.,Percet_ID_var) %>% mutate(., NNNN = as.numeric(n())) %>%
      sample_frac(size = per_sample) %>% ungroup %>%
      dplyr::select(., c(2:(combine_col+1)))
    return(stratified_sample_2_sep)
  }
}

