### Weekly Run to Create New Buckets
# For the purposes of reproducibility and code sharing, this file 
# runs a heuristic feature selection method to decide if individual cities should be broken out
# to serve as standalone types in the EB algorithm.  WE use lasso to decide if city behavior differs significantly from 
# country level behavior and keep cities that are significantly WORSE than country.  
# Sample data has been suitably anonymized.  Values do NOT represent actual data from Greece. 
# For simplicity, this code works with cleaned sample data (hence doesn't check inputs) and produces minimal outputs
# Actual users will likely add additional code for data-wrangling and post-processing outputs for dashboards.  

library(tidyverse)
library(lubridate)
library(glmnet)
library(fastDummies)
source("helpers_public.R")

today_dt <- ymd("2020-09-01")

######
# PLF data
plf_data <- read_csv("../sample_input_data_fake/hist_db_working.csv", 
                     col_types = cols( result_id = col_double(),
                                       country = col_character(),
                                       city = col_character(),
                                       date_entry = col_date(format = ""),
                                       point_entry = col_character(),
                                       to_test = col_character(),
                                       test_result = col_character(),
                                       sent_for_test = col_double()
                     ))


plf_data <- clean_hist_plf_data(plf_data, today_dt, "dummy_file.txt")

#Now clip 48 hours (for testing result delays)
plf_data <- plf_data %>% filter(date_entry <= today_dt - 2) 


########
## Creating new buckets based on city information from past data
########
# limit to white/grey-list + sent for test
dat <- plf_data[plf_data$sent_for_test & !plf_data$isCtryFlagged,]
dat$y <- as.integer(dat$test_result == "positive")
dat <- dat[c("eb_type", "city", "y")]

# read in current EB estimates (MAKE SURE WE HAVE ESTIMATES)
eb <- read_csv("../sample_outputs/country_estimates_2020-09-01.csv")  #should match today-dt
dat <- merge(dat, eb[c("eb_type", "eb_prev")]) # currently drops all grey

# get dummies for frequent cities (appear at least 200x and had at least 1 +)
# lower case all cities to help match
dat$city <- tolower(paste(dat$eb_type, dat$city, sep="_"))
tmp <- table(dat$city)
cities <- names(tmp)[which(tmp >= 200)]
cities <- cities[cities %in% unique(dat[dat$y == 1,]$city)]
ind <- which(!(dat$city %in% cities))
dat$city[ind] <- "Other"
tmp <- dummy_cols(dat["city"])
tmp$city <- NULL
tmp$city_Other <- NULL # remove linearly dependent column
dat <- cbind(dat, tmp)

# run LASSO logistic & get predictive cities
# only consider + coefs (i.e., city is MORE risky)
y <- dat$y
x <- as.matrix(dat[,-c(1:3)])
cv <- cv.glmnet(x,y,alpha=1,family="binomial")
coef <- coef(cv, s= cv$lambda.min)
coef <- coef[which(coef != 0 & coef > 0),]

# output a csv of country and city pairs
res <- data.frame()
tmp <- names(coef)[grep("city", names(coef))]
tmp <- strsplit(tmp, "_")
for(i in 1:length(tmp)){
  res[i,1] <- tmp[[i]][2]
  res[i,2] <- tmp[[i]][3]
}
names(res) <- c("country", "city")
write.csv(res, "../sample_outputs/city_types_updated.csv", row.names=FALSE)

