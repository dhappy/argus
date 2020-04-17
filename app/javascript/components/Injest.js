import React from "react"
import PropTypes from "prop-types"
class Injest extends React.Component {
  render () {
    return (
      <React.Fragment>
        Filename: {this.props.filename}
        Book: {this.props.bookId}
      </React.Fragment>
    );
  }
}

Injest.propTypes = {
  filename: PropTypes.string,
  bookId: PropTypes.string
};
export default Injest
