##########################################################################################################

rm(list = ls())

library(data.table)
library(dplyr)
library(lpSolve)
library(sampling)
library(splitstackshape)
#========== Loading Data ==========================#
combine_all <- fread("combine_all.csv", integer64 = "numeric")
str(combine_all)

#StratifiedSampling_1 <- data.frame(combine_all)

f=function(x){
  x<-as.numeric(as.character(x)) 
  x[is.na(x)] = 0  
  x 
}


StratifiedSampling_1 <- data.frame(apply(combine_all[,1:ncol(combine_all)],2,f))
str(StratifiedSampling_1)

View(StratifiedSampling_1[1:100, ])
#StratifiedSampling_1 <- data.frame(combine_all)


for(i in c(1:ncol(StratifiedSampling_1))) {
  
  q= StratifiedSampling_1[,i]
  
  Percentile_ <- quantile(q,c(.99),na.rm = TRUE)
  
  StratifiedSampling_1[,i][StratifiedSampling_1[,i] >Percentile_] <- Percentile_
  
}



ColNames_ = colnames(StratifiedSampling_1)


# determining the percentile values 

Cal_Percentile = data.frame(1:10)

for(i in c(1:ncol(StratifiedSampling_1))) {
  
  q= StratifiedSampling_1[,i]
  
  Percentile_ <- quantile(q,seq(from=.1,to=1,by=.1))
  
  Cal_Percentile[paste("Percentile",ColNames_[i],sep="_")] <- round(Percentile_,digits = 2)
}


Cal_Percentile[,c("X1.10")] = NULL

Percetn_value = seq(from=.1,to=1,by=.1)

Percetn_value = data.frame(Percetn_value)

Cal_Percentile= cbind(Cal_Percentile,Percetn_value)


#print(Cal_Percentile)


# determining the Variables percentile



#if( FALSE == (class(try(InSparklyR(RD_M9 = Sys.getenv("R_DOC_DIR"),RH_M9 = Sys.getenv("R_HOME"), LAP_M9=Sys.getenv("LOCALAPPDATA")),silent = TRUE))=="try-error")){

for ( col_ in 2 : ncol(StratifiedSampling_1))
{
  b=col_
  StratifiedSampling_1[paste("Percet",ColNames_[col_],sep = "_")] <-
    ifelse(StratifiedSampling_1[b]<Cal_Percentile[1,b],Cal_Percentile[1,ncol(Cal_Percentile)],
           ifelse(StratifiedSampling_1[b]>=Cal_Percentile[1,b]&StratifiedSampling_1[b]<Cal_Percentile[2,b],Cal_Percentile[1,ncol(Cal_Percentile)],
                  ifelse(StratifiedSampling_1[b]>=Cal_Percentile[2,b]&StratifiedSampling_1[b]<Cal_Percentile[3,b],Cal_Percentile[2,ncol(Cal_Percentile)],
                         ifelse(StratifiedSampling_1[b]>=Cal_Percentile[3,b]&StratifiedSampling_1[b]<Cal_Percentile[4,b],Cal_Percentile[3,ncol(Cal_Percentile)],                 
                                ifelse(StratifiedSampling_1[b]>=Cal_Percentile[4,b]&StratifiedSampling_1[b]<Cal_Percentile[5,b],Cal_Percentile[4,ncol(Cal_Percentile)], 
                                       ifelse(StratifiedSampling_1[b]>=Cal_Percentile[5,b]&StratifiedSampling_1[b]<Cal_Percentile[6,b],Cal_Percentile[5,ncol(Cal_Percentile)],
                                              ifelse(StratifiedSampling_1[b]>=Cal_Percentile[6,b]&StratifiedSampling_1[b]<Cal_Percentile[7,b],Cal_Percentile[6,ncol(Cal_Percentile)],
                                                     ifelse(StratifiedSampling_1[b]>=Cal_Percentile[7,b]&StratifiedSampling_1[b]<Cal_Percentile[8,b],Cal_Percentile[7,ncol(Cal_Percentile)],
                                                            ifelse(StratifiedSampling_1[b]>=Cal_Percentile[8,b]&StratifiedSampling_1[b]<Cal_Percentile[9,b],Cal_Percentile[8,ncol(Cal_Percentile)],
                                                                   Cal_Percentile[9,ncol(Cal_Percentile)])))))))))     
  
  #}}else{InSparklyR(RD_M9 = Sys.getenv("R_DOC_DIR"),RH_M9 = Sys.getenv("R_HOME"), LAP_M9=Sys.getenv("LOCALAPPDATA"))
}


#View(StratifiedSampling_1[1:100, ])

#head(StratifiedSampling_1)

OnlyPercn = StratifiedSampling_1%>% select(.,starts_with("Percet"))

Col_OnlyPercn = colnames(OnlyPercn)

apply(is.na(StratifiedSampling_1), 2, sum)

str(StratifiedSampling_1)
View(StratifiedSampling_1[1:100, ])

#StratifiedSampling_3 <- StratifiedSampling_1[, c(2:ncol(StratifiedSampling_1))]


stratified_sample_2_sep <- StratifiedSampling_1 %>%
  group_by(.,Percet_GROSS_ARPU_SEP,Percet_NET_ARPU_SEP,Percet_OG_MOU_SEP,Percet_DATA_USAGE_SEP
  ) %>%
  mutate(.,NNNN = as.numeric(n()))%>%
  sample_frac(0.00145,weight=NNNN )%>%
  ungroup%>%
  select(.,c(1:9))


# str(stratified_sample_2)
summary(StratifiedSampling_1$OG_MOU_SEP)
summary(stratified_sample_2_sep$OG_MOU_SEP)


quantile(StratifiedSampling_1$OG_MOU_SEP, c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1))
quantile(stratified_sample_2_sep$OG_MOU_SEP, c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1))


# # These results should be equal
# table(iris$Species) / nrow(stratified_sample_2)
# table(stratified_sample$Species) / nrow(stratified_sample)


colnames(StratifiedSampling_1)



stratified_sample_2_OCT <- StratifiedSampling_1 %>%
  group_by(.,Percet_GROSS_ARPU_OCT,Percet_NET_ARPU_OCT,Percet_OG_MOU_OCT,Percet_DATA_USAGE_OCT
  ) %>%
  mutate(.,NNNN = as.numeric(n()))%>%
  sample_frac(0.00145,weight=NNNN )%>%
  ungroup%>%
  select(.,c(1:9))


summary(StratifiedSampling_1$GROSS_ARPU_OCT)
summary(stratified_sample_2_OCT$GROSS_ARPU_OCT)

quantile(StratifiedSampling_1$OG_MOU_OCT, c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1))
quantile(stratified_sample_2_OCT$OG_MOU_OCT, c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1))


strata_sample_comb <- rbind(stratified_sample_2_sep, stratified_sample_2_OCT)
strata_sample_comb_1 <- subset(strata_sample_comb, !duplicated(strata_sample_comb$CONSUMER_ID))

View(strata_sample_comb_1[1:500, ])

Strata_ARPU_MSISDN <- strata_sample_comb_1[, c("CONSUMER_ID")]

fwrite(Strata_ARPU_MSISDN, "Strata_Apru_50k.csv", row.names = FALSE)
