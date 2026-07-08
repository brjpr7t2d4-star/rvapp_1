// RV Owner App - User-Generated Content for RV-Friendly Places

// Define RVLocation class
class RVLocation {
  constructor(name, type, latitude, longitude, addedBy) {
    this.name = name;
    this.type = type;
    this.latitude = latitude;
    this.longitude = longitude;
    this.addedBy = addedBy; // User who added the location
    this.reviews = []; // Array to hold reviews for each location
    this.createdDate = new Date(); // Track when location was added
  }

  addReview(review) {
    this.reviews.push(review);
  }

  getAverageRating() {
    if (this.reviews.length === 0) return 0;
    const sum = this.reviews.reduce((total, review) => total + review.rating, 0);
    return (sum / this.reviews.length).toFixed(2);
  }
}

// Define Review class
class Review {
  constructor(username, comment, rating, photo) {
    this.username = username;
    this.comment = comment;
    this.rating = rating; // Rating out of 5
    this.photo = photo; // URL or path to the photo
    this.createdDate = new Date();
  }
}

// Define User class
class User {
  constructor(username) {
    this.username = username;
    this.reviews = []; // Array to hold user reviews
    this.locationsAdded = 0; // Track locations added by user
  }

  addReview(review) {
    this.reviews.push(review);
  }

  incrementLocationsAdded() {
    this.locationsAdded++;
  }
}

// Define RVOwnerApp class
class RVOwnerApp {
  constructor() {
    this.rvLocations = [];
    this.users = []; // Array to hold user accounts
  }

  addRVLocation(name, type, latitude, longitude, addedBy) {
    // Validate that user exists
    const user = this.users.find(u => u.username === addedBy);
    if (!user) {
      console.log(`Error: User ${addedBy} does not exist. Please create an account first.`);
      return false;
    }

    // Validate coordinates
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      console.log('Error: Invalid coordinates. Latitude must be between -90 and 90, Longitude between -180 and 180.');
      return false;
    }

    const location = new RVLocation(name, type, latitude, longitude, addedBy);
    this.rvLocations.push(location);
    user.incrementLocationsAdded();
    console.log(`✓ Added location: ${name} by ${addedBy}`);
    return true;
  }

  createUser(username) {
    // Check if user already exists
    if (this.users.find(u => u.username === username)) {
      console.log(`Error: User ${username} already exists.`);
      return false;
    }

    const user = new User(username);
    this.users.push(user);
    console.log(`✓ User ${username} created successfully.`);
    return true;
  }

  displayRVLocations() {
    if (this.rvLocations.length === 0) {
      console.log('No RV locations available.');
      return;
    }

    console.log('\n--- RV Locations ---');
    this.rvLocations.forEach((location, index) => {
      const avgRating = location.getAverageRating();
      console.log(
        `${index + 1}: ${location.name} - ${location.type} (Added by: ${location.addedBy}, Rating: ${avgRating}/5, Reviews: ${location.reviews.length})`
      );
      console.log(`   Location: (${location.latitude}, ${location.longitude})`);
    });
    console.log('');
  }

  findRVLocationsByType(type) {
    const results = this.rvLocations.filter(location => location.type.toLowerCase() === type.toLowerCase());
    console.log(`\n--- RV Locations of type: ${type} ---`);
    if (results.length === 0) {
      console.log(`No locations found of type: ${type}`);
    } else {
      results.forEach((location, index) => {
        const avgRating = location.getAverageRating();
        console.log(`${index + 1}: ${location.name} (Rating: ${avgRating}/5)`);
      });
    }
    console.log('');
    return results;
  }

  // Add Review to a location
  addReviewToLocation(locationIndex, username, comment, rating, photo = null) {
    // Validate rating
    if (rating < 1 || rating > 5) {
      console.log('Error: Rating must be between 1 and 5.');
      return false;
    }

    const location = this.rvLocations[locationIndex];
    if (location) {
      const review = new Review(username, comment, rating, photo);
      location.addReview(review);
      
      // Add review to user's profile
      const user = this.users.find(u => u.username === username);
      if (user) {
        user.addReview(review);
      }

      console.log(`✓ Review added successfully to ${location.name}.`);
      return true;
    } else {
      console.log('Error: Invalid location index. Review addition failed.');
      return false;
    }
  }

  // Display reviews for a specific location
  displayReviewsForLocation(index) {
    if (index >= 0 && index < this.rvLocations.length) {
      const location = this.rvLocations[index];
      console.log(`\n--- Reviews for ${location.name} ---`);
      
      if (location.reviews.length === 0) {
        console.log('No reviews yet.');
      } else {
        location.reviews.forEach((review, reviewIndex) => {
          console.log(`${reviewIndex + 1}: ${review.username} - ${review.comment} (Rating: ${review.rating}/5)`);
          if (review.photo) {
            console.log(`   Photo: ${review.photo}`);
          }
          console.log(`   Posted: ${review.createdDate.toLocaleDateString()}`);
        });
      }
      console.log('');
    } else {
      console.log('Error: Invalid index. Cannot display reviews.');
    }
  }

  // Display user statistics
  displayUserStatistics(username) {
    const user = this.users.find(u => u.username === username);
    if (!user) {
      console.log(`Error: User ${username} not found.`);
      return;
    }

    console.log(`\n--- Statistics for ${username} ---`);
    console.log(`Locations Added: ${user.locationsAdded}`);
    console.log(`Total Reviews Written: ${user.reviews.length}`);
    if (user.reviews.length > 0) {
      const avgRating = (user.reviews.reduce((sum, r) => sum + r.rating, 0) / user.reviews.length).toFixed(2);
      console.log(`Average Rating Given: ${avgRating}/5`);
    }
    console.log('');
  }

  // Get locations by user
  getLocationsByUser(username) {
    return this.rvLocations.filter(location => location.addedBy === username);
  }

  // Search locations by name
  searchLocationsByName(searchTerm) {
    const results = this.rvLocations.filter(location =>
      location.name.toLowerCase().includes(searchTerm.toLowerCase())
    );
    console.log(`\n--- Search results for "${searchTerm}" ---`);
    if (results.length === 0) {
      console.log('No locations found matching your search.');
    } else {
      results.forEach((location, index) => {
        const avgRating = location.getAverageRating();
        console.log(`${index + 1}: ${location.name} - ${location.type} (Rating: ${avgRating}/5)`);
      });
    }
    console.log('');
    return results;
  }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { RVOwnerApp, RVLocation, Review, User };
}

// Example usage (uncomment to run standalone)
/*
const myRVApp = new RVOwnerApp();

// Create users
myRVApp.createUser('Alice123');
myRVApp.createUser('Bob456');
myRVApp.createUser('CharlieDev');

// Add sample RV locations
myRVApp.addRVLocation('RV Park 1', 'Parking', 40.7128, -74.0060, 'Admin');
myRVApp.addRVLocation('Rest Area 1', 'Rest Area', 34.0522, -118.2437, 'Admin');
myRVApp.addRVLocation('RV Park 2', 'Parking', 37.7749, -122.4194, 'Admin');

// Users can add new RV-friendly places
myRVApp.addRVLocation('Scenic Viewpoint', 'Sightseeing', 36.7783, -119.4179, 'Alice123');
myRVApp.addRVLocation('Mountain Campground', 'Camping', 34.0522, -118.2437, 'Bob456');

// Display all RV locations
myRVApp.displayRVLocations();

// Add reviews with photos to RV locations
myRVApp.addReviewToLocation(0, 'Alice123', 'Great place to park!', 5, 'photo1.jpg');
myRVApp.addReviewToLocation(0, 'Bob456', 'Really enjoyed the amenities.', 4, 'photo2.jpg');
myRVApp.addReviewToLocation(1, 'Alice123', 'Nice rest area but can be crowded.', 3, 'photo3.jpg');
myRVApp.addReviewToLocation(2, 'CharlieDev', 'Excellent location with great views.', 5, 'photo4.jpg');

// Display reviews for a location
myRVApp.displayReviewsForLocation(0);

// Search by type
myRVApp.findRVLocationsByType('Parking');
myRVApp.findRVLocationsByType('Camping');

// Search by name
myRVApp.searchLocationsByName('Park');

// Display user statistics
myRVApp.displayUserStatistics('Alice123');
myRVApp.displayUserStatistics('Bob456');

// Get locations added by a user
console.log('\n--- Locations added by Alice123 ---');
const aliceLocations = myRVApp.getLocationsByUser('Alice123');
aliceLocations.forEach(loc => console.log(`- ${loc.name}`));
*/
