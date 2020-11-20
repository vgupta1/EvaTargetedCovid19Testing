# EvaTargetedCovid19Testing
Open-Source code for Project Eva:  A Targeted Testing Protocol for Greece
----

In the interest of reproducibility, this repo contains open-source code implementing the key **estimation** and **targeted testing** steps of the algorithm underlying Project Eva.  For policy makers and researchers seekign to implement similar systems, please feel free to reach out to the authors below for clarification or help.    



> :warning: **All sample data provided is SYNTHETIC** 

> Inputs and outputs do _not_ represent actual prevalence of Covid19 in Greece or any other nation.



## Citing this work
Team Eva is currently drafting a research paper with the mathematical details of these algorithms in addition to empirical evidence from the summer of 2020 on the effectiveness of Eva.  In the meantime, should you need to cite this work, we politely ask you use the following citation:




## About Team Eva
Team Eva consists of 4 core members:
* [Hamsa Bastani](https://hamsabastani.github.io/), The Wharton School, U. of Pennysylvania 
* [Kimon Drakopoulos](https://www.kimondrakopoulos.com/), USC Marshall School of Business
* [Vishal Gupta](http://faculty.marshall.usc.edu/Vishal-Gupta/), USC Marshall School of Business
* [Jon Vlachogiannis](https://www.linkedin.com/in/johnvlachoyiannis/), Founder of Agent Risk and Software Architect

Please feel free to reach out to Vishal Gupta above for questions/clarifications on the repository. 


## Background on Project Eva
Project Eva is a real-time, targeted testing protocol that we deployed in Greece over the summer of 2020.  The full protocol involves a system in which 
 1. Potential Travelers fill out a PLF Form at least 24 hours in advance of travel 
 2. Information from this PLF form is used to target a small fraction of travelers for testing upon arrival, subject to testing budget constraints at the various 41 points of entry 
 3. Tested Travelers are asked to self-quarrantine until results return iv) Samples from travelers that are tested are processed by a lab in (at most) 48 hours 
 4. Travelers that are found to be positive are quarrantined and contact tracing begins
 5. All results are fed back into the system to update estimates and targeting procedures for future travelers
 
 In this way, the system is ``closed-loop" and updates constantly as the state of the world evolves.  
 
 Necessarily, in addition to the underlying mathematical algorithm, Eva involves integrating many databases across multiple government agencies, securely handling sensitive information, and coordinating databases in nearly real time.  This repository _only_ contains code related to the actual estimation of prevalence and targeting algorithms.  In deployment (and here) it works only with anonymized data.  (The data used here is again synthetic and not representative of actual prevalence rates.)   

For more details on Project Eva, please see:
* (USC Press Release on Project Eva)[https://pressroom.usc.edu/reopen-greek-economy/]
* (A Webinar with Kimon and Vishal)[https://www.marshall.usc.edu/news/project-eva-ai-covid-and-greek-tourism]
* (Vishal's Informs Talk on Project Eva)[]  (only available to INFORMS Members)
* (Kimon's Informs Talk on Project Eva[]    (only available to INFORMS Members)


## Structure of Repository

