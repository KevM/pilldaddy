There is a universal standard for this exact use case: **HL7 FHIR (Fast Healthcare Interoperability Resources)**.
Pronounced "fire," this is the modern, REST-based web standard used across the entire healthcare industry. Major Electronic Health Record (EHR) systems like **Epic, Cerner (Oracle Health), and Meditech** natively use FHIR APIs to send, receive, and parse patient data.
If you want your caregiving app to cleanly export data that a clinic can ingest electronically, you should structure your export around **FHIR Resources** formatted as a **JSON Bundle**.
## 1. The Exact FHIR Resources for Your Data
In the FHIR specification, data is broken down into modular components called "Resources." For your app's core features, you will map your data to three specific resources:
### For Monitoring Metrics (Vitals, Blood Glucose, etc.)
You will use the **Observation** resource.
 * **How it works:** Every heart rate, blood pressure, or weight entry becomes an individual Observation object.
 * **The Key Code:** To make it readable by Epic, you must tag the observation type with a standard **LOINC code** (Logical Observation Identifiers Names and Codes). For example, Blood Pressure is LOINC code 85354-9. When Epic sees that code, it automatically routes the numbers into the patient's vitals flowsheet.
### For Medications Taken (Your "Routine" Logs)
You will use the **MedicationAdministration** resource.
 * **How it works:** This resource explicitly records *who* took *what* medication, *when*, and in what *quantity*.
 * **The Key Code:** The medication itself must be identified using an **RxNorm code** (the standardized catalog for clinical drugs). When you import a medication from HealthKit, it usually includes this RxNorm ID. Passing this back ensures Epic matches the log to the correct prescription in the doctor's chart.
### For the Collective Export File
You wrap all these individual events into a **Bundle** resource. A Bundle is just a JSON array of resources that tells Epic, *"Here is a batch of chronological health events for this specific patient."*
## 2. The Two Practical Ways to Deliver This Data
While FHIR is the code standard, how you actually *get* it to the provider depends on your development stage and budget.
### Method A: The Patient Portal Attachment (Simplest & Best for V1)
Directly integrating with Epic's API network requires your app to go through a formal vendor vetting process. As an independent or early-stage developer, the cleanest bridge is to generate a dual-purpose file.
Provide a **"Share Report with Doctor"** button that compiles:
 1. **A Human-Readable PDF:** A beautifully charted PDF of your **Routines** and metrics. Doctors have about 30 seconds to look at data during a visit; they love clean visual trends.
 2. **A Machine-Readable FHIR JSON File:** Zip the FHIR JSON Bundle together with the PDF.
The caregiver can then send this file directly to their provider via the clinic's existing patient portal (like messaging their care team on **MyChart**). Epic allows providers to drag and drop compliant data files directly into a patient's active chart.
### Method B: The "Epic on FHIR" App Platform (The Scaling Goal)
If you want your app to securely write directly into Epic systems via code in the background, you have to register your app on **fhir.epic.com**.
Epic provides a developer sandbox where you can configure **OAuth 2.0** authentication (using the "SMART on FHIR" standard).
 * The user logs in via your app using their hospital portal credentials.
 * This grants your app a secure token.
 * Your app can then make POST requests to write Observation resources straight to the clinic's database.
> **Development Tip:** Even if you start with Method A, build your internal CoreData or SwiftData schema to mirror the FHIR spec from day one. Map your metrics to LOINC codes and your medications to RxNorm IDs. That way, when you are ready to transition to a live API sync with Epic, your data pipeline is already complete.
