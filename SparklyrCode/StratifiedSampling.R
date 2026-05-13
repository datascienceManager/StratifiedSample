require(data.table)
require(dplyr)



setwd("G:\\BOBR&Adopt\\50K_KOL\\StratifiedSampling")

dir()

StratifiedSampling = fread("StratifiedSampling.csv")

f=function(x){
  x<-as.numeric(as.character(x)) 
  x[is.na(x)] = 0  
  x 
}


StratifiedSampling_1 <- data.frame(apply(StratifiedSampling[,1:ncol(StratifiedSampling)],2,f))


# View(StratifiedSampling_1)

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


# View(StratifiedSampling_1)

#head(StratifiedSampling_1)

OnlyPercn = StratifiedSampling_1%>% select(.,starts_with("Percet"))

Col_OnlyPercn = colnames(OnlyPercn)


stratified_sample_2 <- StratifiedSampling_1 %>%
                       group_by(.,Percet_GROSS_ARPU_SEP,
                                  Percet_NET_ARPU_SEP,
                                  Percet_OG_MOU_SEP,
                                  Percet_DATA_USAGE_SEP
                               ) %>%
                       mutate(.,NNNN = as.numeric(n()))%>%
                       sample_frac(0.4,weight=NNNN )%>%
                       ungroup%>%
                       select(.,c(1:9))


# str(stratified_sample_2)
# str(StratifiedSampling_1)
summary(StratifiedSampling_1$OG_MOU_OCT)
summary(stratified_sample_2$OG_MOU_OCT)

View(stratified_sample_2)

# # These results should be equal
# table(iris$Species) / nrow(stratified_sample_2)
# table(stratified_sample$Species) / nrow(stratified_sample)


getwd()

