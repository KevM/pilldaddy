# Pill Daddy

This iOS app is for care givers who need to track health metrics and medication intake. 

It should integrate with Apple Health to record metrics like:
- Medications
- Blood Pressure
- Pulse / Oxygen %
- Weight
- Water Intake
- Sleep Quality

## Medication 

The elderly often take many medications and different times and with different requirements such as with meals, or before meals etc. 

- Color coded pill regime: batches of medications taken at certain times. 
  - Color manager configure what pills are in each batch 
- Dose change notes to capture why a dose was changing. There should be continuity for a medication across changes in dosage. Medications should be linkable to communicate care continuity such as one beta blocker being swapped out for another. 
- Reporting about historic doses per drug.
  - Be able to swap view from showing when drug was taken vs. when it was not taken. 
  - Present

## Storage 

- iCloud data for durability 
- Metrics should sync to Apple Health. Two way sync is not important for now.

## CI/CD & Deployment

The static marketing website located in the `web/` folder is automatically deployed to Vercel upon successful completion of the **CI** workflow on the `main` branch. 

To enable this automation, the following GitHub Secrets must be configured in your repository settings:

* `VERCEL_TOKEN`: Your Vercel Personal Access Token (for authentication).
* `VERCEL_ORG_ID`: Your Vercel Organization or User account ID.
* `VERCEL_PROJECT_ID`: The unique Project ID of your PillDaddy Vercel project.

