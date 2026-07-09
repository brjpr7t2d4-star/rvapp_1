# RV Owner App - User-Generated Content Feature

A Node.js application that enables RV travelers to discover, submit, and review RV-friendly locations during their travels.

## Features

✨ **User-Generated Content**: Allow users to submit new RV-friendly locations  
⭐ **Reviews & Ratings**: Users can leave detailed reviews with photos and ratings (1-5 stars)  
🔍 **Search & Filter**: Find locations by type (camping, parking, rest areas, etc.) or by name  
👤 **User Profiles**: Track user contributions and statistics  
📍 **Location Data**: Store comprehensive location information with coordinates  
📊 **Analytics**: View average ratings, review counts, and user contribution stats  

## Installation

```bash
npm install
```

## Usage

### Run Example Demo

```bash
npm run demo
```

### Run Signup Tracking API

```bash
npm start
```

API endpoints:
- `POST /api/signup-events` - store a new account creation event
- `GET /api/signup-events` - list all signup events
- `GET /api/signup-stats` - quick totals and daily counts

Signup events are stored in `js-backend/data/signup-events.json`.

### Connect Flutter App To Tracking API

Pass the backend URL when launching Flutter:

```bash
flutter run --dart-define=SIGNUP_TRACKING_API_BASE_URL=http://YOUR_MACHINE_IP:3000
```

Use your Mac's LAN IP for physical iPhone testing (not `localhost`).

### Import in Your Project

```javascript
const { RVOwnerApp, RVLocation, Review, User } = require('./RVOwnerApp');

const app = new RVOwnerApp();
```

## API Documentation

### RVOwnerApp Class

#### Methods

##### `createUser(username)`
Creates a new user account.

```javascript
app.createUser('Alice123');
// Output: ✓ User Alice123 created successfully.
```

**Parameters:**
- `username` (string): Unique username

**Returns:** boolean - true if successful, false if user already exists

---

##### `addRVLocation(name, type, latitude, longitude, addedBy)`
Adds a new RV-friendly location.

```javascript
app.addRVLocation('Yosemite Viewpoint', 'Sightseeing', 37.8651, -119.5383, 'Alice123');
// Output: ✓ Added location: Yosemite Viewpoint by Alice123
```

**Parameters:**
- `name` (string): Location name
- `type` (string): Location type (Parking, Camping, Rest Area, Sightseeing, etc.)
- `latitude` (number): Geographic latitude (-90 to 90)
- `longitude` (number): Geographic longitude (-180 to 180)
- `addedBy` (string): Username of person adding the location

**Returns:** boolean - true if successful

---

##### `addReviewToLocation(locationIndex, username, comment, rating, photo)`
Adds a review to a specific location.

```javascript
app.addReviewToLocation(0, 'Bob456', 'Great spot!', 5, 'photo.jpg');
// Output: ✓ Review added successfully to [Location Name].
```

**Parameters:**
- `locationIndex` (number): Index of the location in the rvLocations array
- `username` (string): Username of reviewer
- `comment` (string): Review text
- `rating` (number): Rating 1-5
- `photo` (string, optional): URL/path to photo

**Returns:** boolean - true if successful

---

##### `displayRVLocations()`
Displays all RV locations with summary information.

```javascript
app.displayRVLocations();
```

**Output:**
```
--- RV Locations ---
1: Yosemite Viewpoint - Sightseeing (Added by: Alice123, Rating: 4.5/5, Reviews: 2)
   Location: (37.8651, -119.5383)
```

---

##### `findRVLocationsByType(type)`
Finds and displays locations of a specific type.

```javascript
app.findRVLocationsByType('Camping');
```

**Parameters:**
- `type` (string): Location type to search for

**Returns:** array of matching RVLocation objects

---

##### `searchLocationsByName(searchTerm)`
Searches for locations by name (case-insensitive).

```javascript
app.searchLocationsByName('Lake');
```

**Parameters:**
- `searchTerm` (string): Search term

**Returns:** array of matching RVLocation objects

---

##### `getLocationsByUser(username)`
Gets all locations added by a specific user.

```javascript
const locations = app.getLocationsByUser('Alice123');
```

**Parameters:**
- `username` (string): Username to search for

**Returns:** array of RVLocation objects

---

##### `displayReviewsForLocation(index)`
Displays all reviews for a specific location.

```javascript
app.displayReviewsForLocation(0);
```

**Parameters:**
- `index` (number): Index of the location

---

##### `displayUserStatistics(username)`
Shows user contribution and review statistics.

```javascript
app.displayUserStatistics('Alice123');
```

**Parameters:**
- `username` (string): Username

**Output:**
```
--- Statistics for Alice123 ---
Locations Added: 2
Total Reviews Written: 5
Average Rating Given: 4.6/5
```

---

### RVLocation Class

#### Properties
- `name` (string): Location name
- `type` (string): Location type
- `latitude` (number): Geographic latitude
- `longitude` (number): Geographic longitude
- `addedBy` (string): Username of contributor
- `reviews` (array): Array of Review objects
- `createdDate` (Date): When location was added

#### Methods

##### `addReview(review)`
Adds a review to the location.

```javascript
const review = new Review('User', 'Great place!', 5, 'photo.jpg');
location.addReview(review);
```

---

##### `getAverageRating()`
Calculates and returns average rating.

```javascript
const avgRating = location.getAverageRating();
// Returns: "4.5"
```

**Returns:** string - Average rating as a 2-decimal number

---

### Review Class

#### Properties
- `username` (string): Reviewer username
- `comment` (string): Review text
- `rating` (number): Rating 1-5
- `photo` (string): Photo URL/path
- `createdDate` (Date): When review was posted

---

### User Class

#### Properties
- `username` (string): Unique username
- `reviews` (array): User's reviews
- `locationsAdded` (number): Count of locations added

#### Methods

##### `addReview(review)`
Adds a review to user's profile.

---

## Example Workflow

```javascript
const { RVOwnerApp } = require('./RVOwnerApp');

const app = new RVOwnerApp();

// 1. Create users
app.createUser('TravelerAlice');
app.createUser('CampingBob');

// 2. Add locations
app.addRVLocation('Lake Tahoe', 'Camping', 39.0968, -120.0324, 'TravelerAlice');
app.addRVLocation('Desert View', 'Sightseeing', 36.2325, -116.8292, 'CampingBob');

// 3. Add reviews
app.addReviewToLocation(0, 'CampingBob', 'Beautiful and clean!', 5, 'tahoe.jpg');
app.addReviewToLocation(1, 'TravelerAlice', 'Stunning sunsets', 4);

// 4. Search and display
app.displayRVLocations();
app.findRVLocationsByType('Camping');
app.displayReviewsForLocation(0);
app.displayUserStatistics('TravelerAlice');
```

## Data Validation

- **Coordinates**: Latitude -90 to 90, Longitude -180 to 180
- **Ratings**: Must be 1-5
- **Usernames**: Must be unique
- **User Requirement**: Users must exist before adding locations or reviews

## License

MIT
