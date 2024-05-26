// Function that tells Assessors that Javascript has been implemented
function alert1050() {
    alert("Javascript Implemented\n\n1. Click on the 'Analyse', 'Improve', 'Maintain'\n\n2. Counter that counts up for the Side by Side content");
}

// Function to display the content of the clicked button
function onclickAnalyse() {
    document.getElementById("analyse").style.display = "block";
    document.getElementById("improve").style.display = "none";
    document.getElementById("maintain").style.display = "none";
}

function onclickImprove() {
    document.getElementById("analyse").style.display = "none";
    document.getElementById("improve").style.display = "block";
    document.getElementById("maintain").style.display = "none";
}

function onclickMaintain() {
    document.getElementById("analyse").style.display = "none";
    document.getElementById("improve").style.display = "none";
    document.getElementById("maintain").style.display = "block";
}

// Function to check if element is in view
function isElementInView(element) {
    var rect = element.getBoundingClientRect();
    return (
        rect.top >= 0 &&
        rect.left >= 0 &&
        rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
        rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
}

// Function to count numbers up when element is in view
function countInView() {
    $('.count').each(function () {
        if (isElementInView(this)) {
            $(this).prop('Counter', 0).animate({
                Counter: $(this).text()
            }, {
                duration: 10000,
                easing: 'swing',
                step: function (now) {
                    $(this).text(Math.ceil(now));
                }
            });
        }
    });
}

// Call countInView function when the page is scrolled or resized
$(window).on('scroll resize', countInView);

// Call countInView function initially to check if any elements are already in view
countInView();



