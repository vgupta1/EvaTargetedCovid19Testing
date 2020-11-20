# EvaTargetedCovid19Testing
Open-Source code for Project Eva:  A Targeted Testing Protocol for Greece
----

<p align="center">
  <img width="250"  src="https://pressroom.usc.edu/files/2020/07/Greece-Covid-web.104655.jpg">
</p>
In the interest of reproducibility, this repository contains open-source code implementing the key *estimation* and *targeted testing* steps of the algorithm underlying Project Eva.  For policy makers and researchers seeking to implement similar systems, please feel free to reach out to the authors below for clarification or help.    

</br>
</br>
<p align="center" style="font-size:160%;">
  :warning: <strong> All sample data provided is SYNTHETIC </strong> :warning:
  </br>
  Inputs and outputs do _not_ represent actual prevalence of Covid19 in Greece or any other nation.
</p>
</br>
</br>





## Citing this work
Team Eva is currently drafting a research paper with the mathematical details of these algorithms in addition to empirical evidence from the summer of 2020 on the effectiveness of Eva.  In the meantime, should you need to cite this work, we politely ask you use the following citation:

```
@misc{bdgv2020Covid19,
  title={Real-Time, Targeted COVID-19 Testing at the Greek Border},
  author={Bastani, Hamsa and Drakopoulos, Kimon and Gupta, Vishal and Vlachogiannis, Jon},
  url={https://github.com/vgupta1/EvaTargetedCovid19Testing/}
  note={Open-Source Software}
}
```

## About Team Eva
Team Eva consists of 4 core members:
* [Hamsa Bastani](https://hamsabastani.github.io/), The Wharton School, U. of Pennysylvania 
* [Kimon Drakopoulos](https://www.kimondrakopoulos.com/), USC Marshall School of Business
* [Vishal Gupta](http://faculty.marshall.usc.edu/Vishal-Gupta/), USC Marshall School of Business
* [Jon Vlachogiannis](https://www.linkedin.com/in/johnvlachoyiannis/), Founder of Agent Risk and Software Architect

Please feel free to reach out to Vishal Gupta above for questions/clarifications on the repository. 


## Background on Project Eva
Project Eva is a real-time, targeted testing protocol that we deployed in Greece over the summer of 2020.  The full protocol involves a system in which 
 1. Potential travelers fill out a PLF Form at least 24 hours in advance of travel 
 2. Information from this PLF form is used to target a small fraction of travelers for testing upon arrival, subject to testing budget constraints at the various 41 points of entry.  These budgets are determined by the Greek Ministry of Health.  
 3. Tested travelers are asked to self-quarantine until results return
 3. Samples from travelers that are tested are processed by a lab in (at most) 48 hours 
 4. Travelers that are found to be positive are quarantined and contact tracing begins
 5. All results are fed back into the system to update estimates and targeting procedures for future travelers
In this way, the system is "closed-loop" and updates constantly as the state of the world evolves.  
 
Necessarily, in addition to the underlying mathematical algorithm, Eva involves integrating many databases across multiple government agencies, securely handling sensitive information, and coordinating databases in nearly real time.  This repository _only_ contains code related to the actual estimation of prevalence and targeting algorithms.  In deployment (and here) it works only with anonymized data.  (The data used here is again synthetic and not representative of actual prevalence rates.)   

For more details on Project Eva, please see:
* [USC Press Release on Project Eva](https://pressroom.usc.edu/reopen-greek-economy/)
* [Webinar with Kimon and Vishal](https://www.marshall.usc.edu/news/project-eva-ai-covid-and-greek-tourism)

## Overview of Algorithm
As mentioned, the authors are currently drafting research publications documenting Eva's mathematical details.  As a rough description, the underlying algorithm has 3 parts:

### Estimating Prevalences using a Feature-Based Empirical Bayes Method
<img align="right" width="400" src="https://github.com/vgupta1/EvaTargetedCovid19Testing/blob/main/sample_outputs/eb_estimates_by_cntry.png?raw=true">
We define "types" of travelers, and use testing data from the recent past to estimate the COVID19 prevalence for each type via an Empirical Bayes methodology.  In contrast to traditional parametric empirical Bayes approaches using a beta-prior, we use a mixture prior informed by features of the various traveler types.  Updates with this prior are straightforward, and yield beta posteriors for each traveler type.  These estimates are used to inform various dashboards (not included in repository), including, e.g., the one at right (included in *sample_outputs/*). 

The model and algorithm allow for very granular definitions of "type" (e.g. men from Los Angeles, CA, USA between the age of 30-40 traveling alone who have not visited any other countries in last 2 weeks) and also very rich features in defining the prior. In deployment, we periodically reassessed to fit the highest-fidelity model reasonably supported by the quality and quantity of data available at that time.  

For most of the summer, passenger types were defined as the country of origin for _most_ passengers, the exception being passengers from the select set of city/states listed in _city_types.csv_.  (More on how these cities were chosen below.)  The prior was defined as mixture prior, with 3 beta components, for each of 1) "Black-listed" types for countries not on the _countries_allowed.csv_ list (discussed below) 2) "Grey-Listed" types from countries for which a negative PCR test was required prior to travel and 3) "White-listed" types for the remainder.  Sample code in this repository follows this structure.


### Targeting Passengers Based on a Batched Bandit
Given beta-posteriors, we target passengers scheduled to arrive for testing via Batched Bandit algorithm. We use a one-step lookahead approximation to the Gittins index to appropriately balance exploration and exploitation, and a customized heuristic to ensure that testing allocations respect the budgets at each port of entry while accounting for the (sometimes significant) incidence of "no-shows" (passengers who are scheduled to arrive who cancel their trip last minute).  We note that due to operational constraints, this step is performed once daily, meaning in each "batch" of the bandit we are assigning aproximately 8K tests to approximately 60K potential passengers.  (The sample data provided is smaller than these representative numbers).  


### Identifying "Special" City/States in Type Definition
As mentioned, we periodically revisit the definition of "type" in the algorithm to allow for the finest granularity possible.  As a heuristic, we use recent data to fit a logistic regression to predict observed prevalence using our empirical bayes estimates and city of origin as features, combined with a lasso penalty.  Any cities that have positive coefficients in the resulting fit are broken out as separate types from their parent country.  

## Structure of Repository
Code is written in R and located in the folder _src/_. The code is written in R and is mostly easily accessed via the R-Studio Project included in the folder.  
 - _dailyRun.r_ executes the empirical bayes fitting and bandit allocation described above.  All outputs are written to _/sample_outputs/_  
 - _featureCheck.R_ performs the analysis above to identify potentially significant additional types to add.  This file requires that dailyRun.r was run previously before running as it uses outputs from _/sample_outputs/_ in the procedure.

This algorithm references various data sources in the folder *sample_input_data_fake/*.  In deployment, these data sources are populated by Eva's backend databases with realtime data from the last 16 days (*hist_db_working.csv*) and all travelers scheduled to arrive tomorrow (*pass_manifest.csv*).  The remaining files are "static data" that is updated periodically in consultation with the Greek Government Covid19 Taskforce, including
 - *port_budgets.csv* : The number of tests available at each port of entry on a daily basis.
 - *countries_allowed.csv* : The list of countries that are permitted to travel to Greece.  This list is developed in conjuction with the European Union.
 - *grey_list_start_end.csv* : Travelers from these countries are required to demonstrate a negative PCR test before travel.  This list is updated periodically in consultation with the Greek Government Covid19 Taskforce based on Eva's estimates of Covid19 Prevalence and public data on reported cases.  
 - *city_types.csv* : As discussed above, a list of special cities to be treated separately when defining types. 

Again, we stress that the data provided in this repository are synthetic.




