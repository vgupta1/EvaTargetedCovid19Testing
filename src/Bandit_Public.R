## Main Gittins index bandit implementation; can be called with different params 
## if data unavailable, pass NULL for manifest ports, and types and it will use some default local data
## g - discount factor MUST be supplied
gittinsBandit <- function(manifest, ports, types, g){
  # INPUTS:
  # #####  manifest has passenger IDs, type, port
  # #####  ports has entry #, remaining testing budget
  # #####  types (curr country) has allowable country, current posterior estimates for a & b
  # #####  g multiplicative factor for exploration
  
  # rename some vars
  ports <- rename(ports, portID=Entry_point, testsLeft = updated_capacity)
  
  manifest <- rename(manifest, Country=eb_type, portID=point_entry)
  types <- rename(types, Country=eb_type, a=alpha.post, b=beta.post, n=num_tested)
  
  # convert factors to char
  manifest$Country <- as.character(manifest$Country)
  manifest$portID  <- as.character(manifest$portID)
  types$Country    <- as.character(types$Country)
  ports$portID     <- as.character(ports$portID)
  
  #Get total tests
  N = round(sum(ports$testsLeft))
  
  # create table to store Gittins index for each allowable country
  gittins <- types
  gittins[,"index"] = NA
  gittins[,"numLeft"] = NA
  gittins[,"alloc"] = 0
  
  #Artificial widening to encourage some exploration
  gittins$a <- gittins$a/10
  gittins$b <- gittins$b/10
  
  # set everyone to initially not test
  manifest$to_test <- FALSE
  
  # randomly permute manifest across ports
  manifest <- manifest[sample(nrow(manifest)),]
  
  # sort ports by remaining tests left
  ports <- ports[order(ports$testsLeft, decreasing = TRUE),]
  
  # first compute index for each country
  for(i in 1:nrow(gittins)){
    
    # get params (WIDENING: add .5 to a and b when computing index)
    # artificial certainty-equivalent update for tests in last 48 hours
    succ = gittins[i, "a"]/(gittins[i, "a"] + gittins[i, "b"])
    a = gittins[i,"a"] + gittins[i,"tests_last_48"] * succ  + 0.5
    b = gittins[i,"b"] + gittins[i,"tests_last_48"] * (1 - succ)  + 0.5
    
    # compute gittins index
    f <- function(x) (x - (a/(a+b))*(1 - g*pbeta(x, a+1, b)) + g*x*(1 - pbeta(x, a, b)))
    gittins[i, "index"] <- uniroot(f, c(0,1))$root
    
    # compute number passengers left from this country that can be tested
    gittins[i,"numLeft"] <- sum(manifest$Country == gittins$Country[i])
  }
  
  gittins[order(gittins$index, decreasing = TRUE),]
  
  ### save initial gittins table (archival w/ date & sample outputs)
  write.csv(gittins[c("Country", "a", "b", "n", "index")], file=
              paste("../sample_outputs/country_gittins_", today(), ".csv", sep=""), row.names=FALSE)
  
  # remove countries with no passengers to test OR no tests left at relevant ports
  rem_ports <- ports[ports$testsLeft > 0, "portID"]
  rem_countries <- unique(manifest[manifest$portID %in% rem_ports & manifest$to_test == FALSE, "Country"])
  gittins <- gittins[gittins$numLeft > 0 & gittins$Country %in% rem_countries,]
  
  # allocate tests one by one, & re-compute indices until (we run out of tests or types to test)
  while(N > 0 & nrow(gittins) > 0){
    
    # allocate test to highest index
    loc <- gittins[which.max(gittins$index), "Country"]
    ind_loc <- which.max(gittins$index)
    
    # pick first untested passenger from that country (at a port with most tests left) to test
    ind <- which(manifest$to_test == FALSE & manifest$Country == loc & manifest$portID %in% rem_ports)
    # look at possible ports & pick the one w/ most tests; THEN pick a passenger
    tmp <- ports[ports$portID %in% manifest[ind, "portID"],]$portID[1]
    ind <- which(manifest$to_test == FALSE & manifest$Country == loc & manifest$portID == tmp)[1]
    manifest[ind, "to_test"] <- TRUE
    
    # update succ, fail, gittins, curr prev (WIDENING: add .5 to a and b when computing index)
    a = gittins[ind_loc, "a"] + gittins[ind_loc, "a"]/(gittins[ind_loc, "a"] + gittins[ind_loc, "b"]) +.5
    b = gittins[ind_loc, "b"] + gittins[ind_loc, "b"]/(gittins[ind_loc, "a"] + gittins[ind_loc, "b"]) +.5
    gittins[ind_loc, c("a", "b", "index")] <- c(a-.5, b-.5, uniroot(f, c(0,1))$root)
    
    # update num passengers left & assign an allocation to that country
    gittins[ind_loc, "numLeft"] <- gittins[ind_loc, "numLeft"] - 1
    gittins[ind_loc, "alloc"] <- gittins[ind_loc, "alloc"] + 1
    
    # update num tests in that port and overall
    ind_port = which(ports$portID == manifest[ind, "portID"])
    ports[ind_port, "testsLeft"] = ports[ind_port, "testsLeft"] - 1
    N = N - 1
    
    # remove countries with no passengers to test OR no tests left at relevant ports
    rem_ports <- ports[ports$testsLeft > 0, "portID"]
    rem_countries <- unique(manifest[manifest$portID %in% rem_ports & manifest$to_test == FALSE, "Country"])
    gittins <- gittins[gittins$numLeft > 0 & gittins$Country %in% rem_countries,]
    
  }
  
  # remove extraneous columns
  manifest <- manifest[c("id", "to_test")]
  
  return(manifest)
}
